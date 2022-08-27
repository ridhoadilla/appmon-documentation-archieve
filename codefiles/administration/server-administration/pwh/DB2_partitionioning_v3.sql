-- This SQL scripts enables Partitioning in a AppMon PWH database for the tables
--   MEASUREMENT_HIGH, PERCENTILES_HIGH
-- Feature-set/description of our new partitioning implementation V2:
--   Fully PL/SQL based partition maintenance implementation, ready to be scheduled in a daily task
--   Creating new (empty) future day partitions to avoid I/O
--   Support for switching/purging out data with a configurable retention time in days
--   Ready to be used on existing data. No need to start with an empty database
--   Optionally automatically updates statistics for both
-- Usage:
--   Run/connect as dba user
--   Before script execution, make sure to create a backup of the database (just in case)
--   Disconnect the AppMon server from the PWH
--   Replace ALL DYNTRC sessions with the real schema name of the AppMon database
--   Search for a local variable called 'declare retentionDays' and adapt the value (in days) according to the High Resolution Duration configuration for the Performance Warehouse in the AppMon client. They MUST match!
--   The last step to finish up the partitioning setup is to enable the option 'Manually manage deletion of high resolution data (for partitioning)' in PWH storage management(AppMon Client).

--!!!!!! Important Set the statement delimiter to @


set current schema "DYNTRC" @

create or replace function F_DBDATE2JAVALONG ( pDbDate timestamp)
	returns BigInt
	language sql
	contains sql
	no external action
	deterministic
	return (CAST(days(pDbDate) - days('1970-01-01-00.00.00.000000') as BigInt)*86400 + midnight_seconds(pDbDate))* 1000 + microsecond(pDbDate)/1000
@

create or replace function F_JAVALONG2DBDATE ( IN pJavaLong BigInt )
	returns Date
	language sql
	contains sql
	no external action
	deterministic
	return to_date('01-01-1970', 'DD-MM-YYYY') + (pJavaLong / (86400 * 1000)) DAYS
@

create or replace procedure P_SPLIT_PARTITION(
	pTableName varchar(100)
	, pDayToPartition timestamp
	, pDayDropPartitionThreshold Integer
	, pDoSplitPartition Boolean
	, pDoDropPartitions Boolean
	, pDoUpdateStatistics Boolean)
	language sql
	begin
	declare dDayEnd timestamp;
	declare nDayEnd bigint;
  	declare cCurrentSchema varchar(128);
	declare cCurrentPath varchar(128);
  	declare nYoungestPartition Integer;
	declare cSwichtoutTablename varchar(100) default '_SWITCHOUT';
	declare counter integer;
	declare cNewPartitionName varchar(128);
	declare isSplittingRequired Boolean;
	declare at_end smallint default 0;
	set current schema "DYNTRC";
	values current schema into cCurrentSchema;
	set cSwichtoutTablename = pTableName || cSwichtoutTablename;
	set dDayEnd = to_date(to_char(pDayToPartition, 'YYYY/MM/DD') || ' 23:59:59', 'YYYY/MM/DD HH24:MI:SS');
	set nDayEnd = "DYNTRC".F_DBDATE2JAVALONG( dDayEnd );
	set cNewPartitionName = 'P' || to_char(dDayEnd, 'yyyyMMdd');
	Select count(*) into nYoungestPartition from syscat.datapartitions
	where tabname = pTableName and tabschema = current schema
			and datapartitionname > upper('P' || TO_CHAR(pDayToPartition - 1 DAYS, 'yyyyMMdd')) and datapartitionname like 'P2%';

	if nYoungestPartition = 0 and pDoSplitPartition = true then
		set isSplittingRequired = true;
	else
		set isSplittingRequired = false;
	end if;
	if isSplittingRequired = true then
		-- ADD the new Partition
		--call DBMS_OUTPUT.put_line('ADD Partition: Table ' || pTableName || ' Partition ' || ' Ending ' || nDayEnd );
		execute immediate 'alter table "' || cCurrentSchema || '".' || pTableName || ' ADD PARTITION ' || cNewPartitionName || ' ENDING ' || nDayEnd;
	end if;
	if pDoDropPartitions = true then
		-- look for Partitions to detach
		for i as partitionsToDelete Cursor for
		select datapartitionname from syscat.datapartitions where
			tabname = pTableName and tabschema = current schema
			and datapartitionname < upper('P' || TO_CHAR(current_date + pDayDropPartitionThreshold DAYS, 'yyyyMMdd')) and datapartitionname like 'P2%'
			order by datapartitionname asc
		do
			-- call DBMS_OUTPUT.put_line('Drop ' || pTableName);
			 execute immediate 'alter table "' || cCurrentSchema || '".' || pTableName || ' detach partition ' || datapartitionname || ' into ' || cSwichtoutTablename || datapartitionname;
		end for;
		commit work;
		-- look for ready detached Partitions(tables), type T .. table , access_mode F ..Full access
		for i as switchout Cursor for
		select tabname from syscat.tables where tabschema = cCurrentSchema and type = 'T' and access_mode = 'F' and tabname like cSwichtoutTablename || '%'
		do
			execute immediate 'drop table ' || tabname;
		end for;
		commit work;
	end if;
	end
@

create or replace procedure P_PARTITION(
	pTableName varchar(100)
	, pDayToPartition Integer
	, pDayDropPartitionThreshold Integer
	, pDoSplitPartition Boolean
	, pDoDropPartitions Boolean
	, pDoUpdateStatistics Boolean)
	language sql
	begin
	declare NegativDropPartitiontreshold Integer;
	declare counter Integer;
	declare cCurrentSchema varchar(128);
	values current schema into cCurrentSchema;
	set NegativDropPartitiontreshold = pDayDropPartitionThreshold * -1;
	set counter = NegativDropPartitiontreshold;
	while ( counter < pDayToPartition) do
		--call DBMS_OUTPUT.put_line('Split Partition ' || pTableName);
		call "DYNTRC".P_SPLIT_PARTITION(pTableName , current timestamp + counter DAYS , NegativDropPartitiontreshold, true, true, true);
		set counter = counter + 1;
	end while;
	if pDoUpdateStatistics = true then
		call sysproc.admin_cmd('runstats on Table "' || cCurrentSchema || '".' || pTableName || ' WITH DISTRIBUTION  AND SAMPLED DETAILED INDEXES ALL ALLOW WRITE ACCESS');
	end if;
	end
@

create or replace procedure P_MYLOADDATA(
	pTableNameSource varchar(100)
	, pTableNameTarget varchar(100))
	language sql
	begin
		declare v_version_number INTEGER default 1;
		declare v_cursor_statement VARCHAR(32672);
		declare v_load_command VARCHAR(32672);
		declare v_sqlcode INTEGER default -1;
		declare v_sqlmessage VARCHAR(2048) default '';
		declare v_rows_read BIGINT default -1 ;
		declare v_rows_skipped BIGINT default -1;
		declare v_rows_loaded BIGINT default -1;
		declare v_rows_rejected BIGINT default -1;
		declare v_rows_deleted BIGINT default -1;
		declare v_rows_committed BIGINT default -1;
		declare v_rows_part_read BIGINT default -1;
		declare v_rows_part_rejected BIGINT default -1;
		declare v_rows_part_partitioned BIGINT default -1;
		declare v_mpp_load_summary VARCHAR(32672) default NULL;
	call sysproc.db2load( v_version_number, 'declare transferC CURSOR for select * from ' || pTableNameSource, 'load from transferC of cursor modified by norowwarnings insert into ' || pTableNameTarget || ' nonrecoverable',
				v_sqlcode, v_sqlmessage, v_rows_read, v_rows_skipped,
				v_rows_loaded, v_rows_rejected, v_rows_deleted, v_rows_committed,
				v_rows_part_read, v_rows_part_rejected,
				v_rows_part_partitioned, v_mpp_load_summary);
		call DBMS_OUTPUT.put_line('LOAD: ' || v_sqlcode);
		call DBMS_OUTPUT.put_line('Message: ' || v_sqlmessage);

	end
@
create or replace procedure P_DEFAULT_PARTITIONMEASUREMENT()
	language SQL
	begin
		declare retentionDays integer default 14;
		set current schema "DYNTRC";
		call "DYNTRC".P_PARTITION('MEASUREMENT_HIGH', 14 , retentionDays, true, true, true);
	end
@

create or replace procedure P_DEFAULT_PARTITIONPERCENTILES()
	language SQL
	begin
		declare retentionDays integer default 14;
		set current schema "DYNTRC";
		call "DYNTRC".P_PARTITION('PERCENTILES_HIGH', 14 , retentionDays, true, true, true);
	end
@

set serveroutput on
@
-- Start Initial Setup
begin
-- Measurment_High
	declare retentionDays integer default 14;
	declare dropPartitiontimestamp bigint;
	declare dropPartitiondate varchar(8);
	declare dropPartitionEndingtimestamp bigint;
	declare cCurrentSchema varchar(128);
	values current schema into cCurrentSchema;
	select BIGINT(DAYS(current_timestamp-current_timezone - retentionDays DAYS)-DAYS(timestamp('1970-01-01-00.00.00')) )*86400000 into dropPartitiontimestamp from sysibm.sysdummy1;
	select TO_CHAR(current_date - retentionDays DAYS,'YYYYMMDD') into dropPartitiondate from sysibm.sysdummy1;
	select BIGINT(DAYS(current_timestamp-current_timezone - retentionDays DAYS)-DAYS(timestamp('1970-01-01-00.00.00'))  + 1)*86400000 into dropPartitionEndingtimestamp from sysibm.sysdummy1;
	call DBMS_OUTPUT.put_line('Create Partitioned Table MEASUREMENT_HIGH1 STARTING ' || dropPartitiontimestamp || ' ENDING ' || dropPartitionEndingtimestamp);
	execute immediate 'CREATE TABLE "MEASUREMENT_HIGH1"  ( ' ||
		  '"MEASURE_ID" INTEGER NOT NULL, ' ||
		  '"TIMESTAMP" DECIMAL(20,0) NOT NULL , ' ||
		  '"MINVALUE" DOUBLE  , ' ||
		  '"MAXVALUE" DOUBLE  , ' ||
		  '"SUMVALUE" DOUBLE  , ' ||
		  '"COUNTVALUE" DECIMAL(20,0)' ||
		  ') PARTITION BY RANGE ("TIMESTAMP")' ||
		  '(' ||
		  'PARTITION p' || dropPartitiondate || ' STARTING ' || dropPartitiontimestamp ||' ENDING ' || dropPartitionEndingtimestamp  || ' EXCLUSIVE)';

	execute immediate 'CREATE UNIQUE INDEX PK_MNT_HIGH1 ON MEASUREMENT_HIGH1(measure_id ASC, timestamp ASC) PARTITIONED';

	call "DYNTRC".P_PARTITION('MEASUREMENT_HIGH1', 14 , retentionDays, true, true, true);
	--Load Data into
	call "DYNTRC".P_MYLOADDATA('MEASUREMENT_HIGH','MEASUREMENT_HIGH1');
	execute immediate 'drop table MEASUREMENT_HIGH';
	execute immediate 'rename table MEASUREMENT_HIGH1 to MEASUREMENT_HIGH';
	execute immediate 'rename index PK_MNT_HIGH1 to "PK_MNT_HIGH"';

	-- Percentiles_High
	execute immediate 'CREATE TABLE "PERCENTILES_HIGH1" ( ' ||
		  '"MEASURE_ID" INTEGER  NOT NULL,' ||
		  '"TIMESTAMP" DECIMAL(20,0) NOT NULL, ' ||
		  '"PQUANTILE" DOUBLE, ' ||
		  '"MARKERCOUNT" DECIMAL(2,0), ' ||
		  '"OBSCOUNT" INTEGER,' ||
		  '"MAXIMUM" DOUBLE,' ||
		  '"MINIMUM" DOUBLE,' ||
		  '"OUTLIERCOUNT" INTEGER, ' ||
		  '"MARKERPOS0" INTEGER, ' ||
		  '"MARKERPOS1" INTEGER, ' ||
		  '"MARKERPOS2" INTEGER, ' ||
		  '"MARKERPOS3" INTEGER, ' ||
		  '"MARKERPOS4" INTEGER, ' ||
		  '"MARKERPOS5" INTEGER, ' ||
		  '"MARKERPOS6" INTEGER, ' ||
		  '"MARKERPOS7" INTEGER, ' ||
		  '"MARKERPOS8" INTEGER, ' ||
		  '"MARKERPOS9" INTEGER, ' ||
		  '"MARKERPOS10" INTEGER, ' ||
		  '"MARKERPOS11" INTEGER, ' ||
		  '"MARKERPOS12" INTEGER, ' ||
		  '"MARKERPOS13" INTEGER, ' ||
		  '"MARKERPOS14" INTEGER, ' ||
		  '"MARKERPOS15" INTEGER, ' ||
		  '"MARKERPOS16" INTEGER, ' ||
		  '"MARKERPOS17" INTEGER, ' ||
		  '"MARKERPOS18" INTEGER, ' ||
		  '"MARKERPOS19" INTEGER, ' ||
		  '"MARKERPOS20" INTEGER, ' ||
		  '"MARKERPOS21" INTEGER, ' ||
		  '"MARKERPOS22" INTEGER, ' ||
		  '"MARKERPOS23" INTEGER, ' ||
		  '"MARKERPOS24" INTEGER, ' ||
		  '"MARKERPOS25" INTEGER, ' ||
		  '"MARKERPOS26" INTEGER, ' ||
		  '"MARKERPOS27" INTEGER, ' ||
		  '"MARKERPOS28" INTEGER, ' ||
		  '"MARKERHEIGHT0" DOUBLE, ' ||
		  '"MARKERHEIGHT1" DOUBLE, ' ||
		  '"MARKERHEIGHT2" DOUBLE, ' ||
		  '"MARKERHEIGHT3" DOUBLE, ' ||
		  '"MARKERHEIGHT4" DOUBLE, ' ||
		  '"MARKERHEIGHT5" DOUBLE, ' ||
		  '"MARKERHEIGHT6" DOUBLE, ' ||
		  '"MARKERHEIGHT7" DOUBLE, ' ||
		  '"MARKERHEIGHT8" DOUBLE, ' ||
		  '"MARKERHEIGHT9" DOUBLE, ' ||
		  '"MARKERHEIGHT10" DOUBLE, ' ||
		  '"MARKERHEIGHT11" DOUBLE, ' ||
		  '"MARKERHEIGHT12" DOUBLE, ' ||
		  '"MARKERHEIGHT13" DOUBLE, ' ||
		  '"MARKERHEIGHT14" DOUBLE, ' ||
		  '"MARKERHEIGHT15" DOUBLE, ' ||
		  '"MARKERHEIGHT16" DOUBLE, ' ||
		  '"MARKERHEIGHT17" DOUBLE, ' ||
		  '"MARKERHEIGHT18" DOUBLE, ' ||
		  '"MARKERHEIGHT19" DOUBLE, ' ||
		  '"MARKERHEIGHT20" DOUBLE, ' ||
		  '"MARKERHEIGHT21" DOUBLE, ' ||
		  '"MARKERHEIGHT22" DOUBLE, ' ||
		  '"MARKERHEIGHT23" DOUBLE, ' ||
		  '"MARKERHEIGHT24" DOUBLE, ' ||
		  '"MARKERHEIGHT25" DOUBLE, ' ||
		  '"MARKERHEIGHT26" DOUBLE, ' ||
		  '"MARKERHEIGHT27" DOUBLE, ' ||
		  '"MARKERHEIGHT28" DOUBLE' ||
		  ') PARTITION BY RANGE ("TIMESTAMP")' ||
		  '(' ||
		  'PARTITION p' || dropPartitiondate || ' STARTING ' || dropPartitiontimestamp ||' ENDING ' || dropPartitionEndingtimestamp  || ' EXCLUSIVE)';

	execute immediate 'CREATE UNIQUE INDEX "PK_P_HIGH1" ON PERCENTILES_HIGH1(measure_id ASC, timestamp ASC) PARTITIONED';
	call "DYNTRC".P_PARTITION('PERCENTILES_HIGH1', 14 , retentionDays, true, true, true);
	--Load Data into
	call "DYNTRC".P_MYLOADDATA('PERCENTILES_HIGH','PERCENTILES_HIGH1');
	execute immediate 'drop table PERCENTILES_HIGH';
	execute immediate 'rename table "PERCENTILES_HIGH1" to "PERCENTILES_HIGH"';
	execute immediate 'rename index "PK_P_HIGH1" to "PK_P_HIGH"';


end@
-- Setup Jobs, running at 2 AM
begin
	call sysproc.admin_task_add('Daily Partitioning MeasurementHigh DYNTRC', current_timestamp, null, null, '00 02 * * *', 'DYNTRC', 'P_DEFAULT_PARTITIONMEASUREMENT', null, null, null);
	call sysproc.admin_task_add('Daily Partitioning PercentileHigh DYNTRC', current_timestamp, null, null, '00 02 * * *', 'DYNTRC', 'P_DEFAULT_PARTITIONPERCENTILES', null, null, null);
end@

--END Initial Setup

commit@
