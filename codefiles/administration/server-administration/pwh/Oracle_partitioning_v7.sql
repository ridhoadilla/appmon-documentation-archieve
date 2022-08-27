-- This SQL scripts enables Partitioning in a AppMon PWH database for the tables
--   MEASUREMENT_HIGH, PERCENTILES_HIGH
-- Feature-set/description of our new partitioning implementation V6:
--   Fully PL/SQL based partition maintenance implementation, ready to be scheduled in a daily Oracle job
--   Using an overflow partition with MAXVALUE has highest boundary to ensure continues insertion into partioned tables
--   Creating new (empty) future day partitions to avoid I/O when splitting from overflow partition
--   Support for switching/purging out data with a configurable retention time in days
--   Ready to be used on existing data. No need to start with an empty database
--   Optionally automatically updates statistics for both, the new day and MAXVALUE partition
-- Usage:
--   Run/connect as SYSTEM equivalent user
--   Before script execution, make sure to create a backup of the database (just in case)
--   Disconnect the AppMon server from the PWH
--   Replace <your_schema> with the real schema name of the AppMon database
--   Search for a local variable called 'highRetentionTimeInDays' and adapt the value (in days) according to the High Resolution Duration configuration for the Performance Warehouse in the AppMon client. They MUST match!
--   Search for a local variable called 'percentilesRetentionTimeInDays' and adapt the value (in days) according to your preferences. Default is 60 days.
--   In case of an update from partitioning V2 or greater to V6, simply remove everything between the "START/END Initial Setup ..."
--   The script tries to delete existing daily partitioning jobs from the V2 implementation
--   Preferable, the script should be run with the customer DBA and a member of the PWH R&D team
--   The last step to finish up the partitioning setup is to enable the option 'Manually manage deletion of high resolution data (for partitioning)' in PWH storage management.



-- ADAPT THIS PROPERLY. Use the AppMon PWH schema here!
ALTER SESSION SET current_schema=<your_schema>;
/

ALTER SESSION SET ddl_lock_timeout=86400;

begin
  -- Needed to run split partition on an IOT withing a stored procedure
  execute immediate 'grant create table to ' || sys_context('USERENV', 'CURRENT_SCHEMA');
end;
/

CREATE OR REPLACE FUNCTION F_DBDATE2JAVALONG
(
  pDBDate Date
)
RETURN Number
AS
begin
  return to_number((pDBDate - to_date('01-01-1970','DD-MM-YYYY')) * (86400 * 1000));
end;
/
CREATE OR REPLACE FUNCTION F_JAVALONG2DBDATE
(
  pJavaLong Number
)
RETURN Date
AS
begin
  return  to_date('01-01-1970','DD-MM-YYYY') + (pJavaLong / (86400 * 1000));
end;
/


CREATE OR REPLACE procedure P_SPLIT_PARTITION(
  pTableName VARCHAR2
  , pDayToPartition Date
  , pDayDropPartitionThreshold Integer
  , pDoSplitPartition Boolean
  , pDoDropPartitions Boolean
)
as
  dDayEnd Date;
  nDayEnd number(20);
  cCurrentSchema varchar2(50);
  nYoungestPartition number(20);
  cOverflowPartitionName user_tab_partitions.partition_name%type default 'POVERFLOW';
  par_name user_tab_partitions.partition_name%type;
  cNewPartitionName user_tab_partitions.partition_name%type;
  isSplittingRequired Boolean;

  cursor partitionsToDelete is
    select partition_name from user_tab_partitions
    where
      TABLE_NAME = pTableName
      and partition_name < upper('P' || TO_CHAR(current_date + pDayDropPartitionThreshold, 'yyyyMMdd'))
      and partition_name != upper(cOverflowPartitionName)
    order by
      partition_name asc;
BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET ddl_lock_timeout=86400';

  cCurrentSchema := sys_context('USERENV', 'CURRENT_SCHEMA');
  dDayEnd := to_date(to_char(pDayToPartition, 'YYYY/MM/DD') || ' 23:59:59', 'YYYY/MM/DD HH24:MI:SS');
  nDayEnd := F_DBDATE2JAVALONG(dDayEnd);

  cNewPartitionName := 'P' || to_char(dDayEnd, 'yyyyMMdd');
  Select count(*) into nYoungestPartition from user_tab_partitions
    where
      TABLE_NAME = pTableName  and partition_name > upper('P' || TO_CHAR(pDayToPartition - 1, 'yyyyMMdd'))
      and partition_name != upper(cOverflowPartitionName);
  IF( nYoungestPartition = 0 and pDoSplitPartition) then
    isSplittingRequired := true;
  else
   isSplittingRequired := false;
  end if;

  IF (isSplittingRequired) THEN
    execute immediate '
      alter table ' || pTableName || '
        split partition ' || cOverflowPartitionName || ' at (' || nDayEnd || ')
        into (
          partition ' || cNewPartitionName || '
          , partition ' || cOverflowPartitionName || '
        )
    ';
  END IF;
  IF (pDoDropPartitions) THEN
    OPEN partitionsToDelete;
    LOOP
        FETCH partitionsToDelete into par_name;
        EXIT WHEN partitionsToDelete%NOTFOUND;
        EXECUTE IMMEDIATE 'ALTER TABLE ' || pTableName || ' DROP PARTITION ' || par_name;
    END LOOP;
    CLOSE partitionsToDelete;
  END IF;
END;
/


CREATE OR REPLACE procedure P_PARTITIONING(
  pTableName VARCHAR2
  , pDayToPartition Integer
  , pDayDropPartitionThreshold Integer
  , pDoSplitPartition Boolean
  , pDoDropPartitions Boolean
  , pDoUpdateStatistics Boolean)
  as
  NegativDropPartitionTreshold Integer;
  cCurrentSchema varchar2(50);
  begin
  NegativDropPartitionTreshold := pDayDropPartitionThreshold * -1;
  for i IN NegativDropPartitionTreshold..pDayToPartition LOOP
    P_SPLIT_PARTITION(pTableName, current_date + i, NegativDropPartitionTreshold, pDoSplitPartition, pDoDropPartitions);
  end loop;
  if (pDoUpdateStatistics) THEN
    cCurrentSchema := sys_context('USERENV', 'CURRENT_SCHEMA');
	DBMS_STATS.SET_TABLE_PREFS(cCurrentSchema,pTableName, 'INCREMENTAL', 'TRUE');
    dbms_stats.gather_table_stats(
      cCurrentSchema
      , pTableName
    );
  end if;
end;
/

--Start Initial Setup the Tables for Partitioning

CREATE TABLE measurement_high1 (
  measure_id integer
  , timestamp number(20)
  , minvalue binary_double
  , maxvalue binary_double
  , sumvalue binary_double
  , countvalue integer
  , constraint pk_measurement_high1 primary key (measure_id, timestamp)
) organization index
partition by range (timestamp)
(
  partition poverflow values less than (maxvalue)
);


alter table measurement_high1 enable row movement;

alter table measurement_high1 exchange partition poverflow with table measurement_high without validation;

drop table measurement_high purge;

alter table measurement_high1 rename to measurement_high;

alter table measurement_high rename constraint pk_measurement_high1 to pk_measurement_high;

begin
  dbms_stats.gather_table_stats(sys_context('USERENV', 'CURRENT_SCHEMA'), 'measurement_high', 'poverflow', cascade => TRUE);
end;
/

CREATE TABLE PERCENTILES_HIGH1 (
  measure_id INTEGER,
  timestamp NUMBER(20),
  pQuantile BINARY_DOUBLE,
  markercount NUMBER(2),
  obscount INTEGER,
  maximum BINARY_DOUBLE,
  minimum BINARY_DOUBLE,
  outliercount INTEGER,
  markerpos0 INTEGER,
  markerpos1 INTEGER,
  markerpos2 INTEGER,
  markerpos3 INTEGER,
  markerpos4 INTEGER,
  markerpos5 INTEGER,
  markerpos6 INTEGER,
  markerpos7 INTEGER,
  markerpos8 INTEGER,
  markerpos9 INTEGER,
  markerpos10 INTEGER,
  markerpos11 INTEGER,
  markerpos12 INTEGER,
  markerpos13 INTEGER,
  markerpos14 INTEGER,
  markerpos15 INTEGER,
  markerpos16 INTEGER,
  markerpos17 INTEGER,
  markerpos18 INTEGER,
  markerpos19 INTEGER,
  markerpos20 INTEGER,
  markerpos21 INTEGER,
  markerpos22 INTEGER,
  markerpos23 INTEGER,
  markerpos24 INTEGER,
  markerpos25 INTEGER,
  markerpos26 INTEGER,
  markerpos27 INTEGER,
  markerpos28 INTEGER,
  markerheight0 BINARY_DOUBLE,
  markerheight1 BINARY_DOUBLE,
  markerheight2 BINARY_DOUBLE,
  markerheight3 BINARY_DOUBLE,
  markerheight4 BINARY_DOUBLE,
  markerheight5 BINARY_DOUBLE,
  markerheight6 BINARY_DOUBLE,
  markerheight7 BINARY_DOUBLE,
  markerheight8 BINARY_DOUBLE,
  markerheight9 BINARY_DOUBLE,
  markerheight10 BINARY_DOUBLE,
  markerheight11 BINARY_DOUBLE,
  markerheight12 BINARY_DOUBLE,
  markerheight13 BINARY_DOUBLE,
  markerheight14 BINARY_DOUBLE,
  markerheight15 BINARY_DOUBLE,
  markerheight16 BINARY_DOUBLE,
  markerheight17 BINARY_DOUBLE,
  markerheight18 BINARY_DOUBLE,
  markerheight19 BINARY_DOUBLE,
  markerheight20 BINARY_DOUBLE,
  markerheight21 BINARY_DOUBLE,
  markerheight22 BINARY_DOUBLE,
  markerheight23 BINARY_DOUBLE,
  markerheight24 BINARY_DOUBLE,
  markerheight25 BINARY_DOUBLE,
  markerheight26 BINARY_DOUBLE,
  markerheight27 BINARY_DOUBLE,
  markerheight28 BINARY_DOUBLE,
  CONSTRAINT PK_PERCENTILES_HIGH1 PRIMARY KEY
  (
	measure_id ,
	timestamp
   )
) ORGANIZATION INDEX
partition by range (timestamp)
(
  partition poverflow values less than (maxvalue)
);


alter table percentiles_high1 enable row movement;

alter table percentiles_high1 exchange partition poverflow with table percentiles_high without validation;

drop table percentiles_high purge;

alter table percentiles_high1 rename to percentiles_high;

alter table percentiles_high rename constraint pk_percentiles_high1 to pk_percentiles_high;

begin
  dbms_stats.gather_table_stats(sys_context('USERENV', 'CURRENT_SCHEMA'), 'percentiles_high', 'poverflow', cascade => TRUE);
end;
/

--Split the POverflow into several Partitions
DECLARE
    highRetentionTimeInDays INTEGER;
    percentilesRetentionTimeInDays INTEGER;
begin
 -- ADAPT THIS PROPERLY !!!
 highRetentionTimeInDays := 14;
 percentilesRetentionTimeInDays := 60;
 P_PARTITIONING('MEASUREMENT_HIGH',7, highRetentionTimeInDays, true, true, true);
 P_PARTITIONING('PERCENTILES_HIGH',7, percentilesRetentionTimeInDays, true, true, true);
end;

--END Initial Setup the Tables for Partitioning
/

-- DELETE old daily jobs
declare
schema VARCHAR2(500);
jobName ALL_SCHEDULER_JOBS.job_name%type;
cursor jobsToDelete is
    select job_name from ALL_SCHEDULER_JOBS where owner in (SELECT sys_context('USERENV', 'CURRENT_SCHEMA') FROM DUAL) and  (job_name like 'MEASUREMENT%' or job_name like 'PERCENTILES%');
begin
 SELECT sys_context('USERENV', 'CURRENT_SCHEMA') INTO schema FROM DUAL;
 OPEN jobsToDelete;
    LOOP
        FETCH jobsToDelete into jobName;
        EXIT WHEN jobsToDelete%NOTFOUND;
        DBMS_SCHEDULER.DROP_JOB(
          job_name=> schema ||'.' || jobName,
          force => true);
    END LOOP;
    CLOSE jobsToDelete;

end;
/
-- END DELETE old daily jobs

DECLARE
    schema VARCHAR2(500);
    highRetentionTimeInDays INTEGER;
BEGIN
    -- ADAPT THIS PROPERLY !!!
	highRetentionTimeInDays := 14;
    SELECT sys_context('USERENV', 'CURRENT_SCHEMA') INTO schema FROM DUAL;
    dbms_scheduler.create_job(
        job_name => schema || '.MEASUREMENT_HIGH_PART_JOB_V6',
        job_type => 'PLSQL_BLOCK',
        job_action => schema || '.P_PARTITIONING(''MEASUREMENT_HIGH'', 7, ' || highRetentionTimeInDays || ', true, true, true);',
        repeat_interval => 'FREQ=DAILY;BYHOUR=1;BYMINUTE=0;BYSECOND=0',
        start_date => systimestamp at time zone '0:00',
        comments => 'Daily job to manage partitions on MEASUREMENT_HIGH',
        auto_drop => FALSE,
        enabled => TRUE
    );
END;
/

DECLARE
    schema VARCHAR2(500);
    percentilesRetentionTimeInDays INTEGER;
BEGIN
    percentilesRetentionTimeInDays := 60;
    SELECT sys_context('USERENV', 'CURRENT_SCHEMA') INTO schema FROM DUAL;
    dbms_scheduler.create_job(
        job_name => schema || '.PERCENTILES_HIGH_PART_JOB_V6',
        job_type => 'PLSQL_BLOCK',
        job_action => schema || '.P_PARTITIONING(''PERCENTILES_HIGH'', 7, ' || percentilesRetentionTimeInDays || ', true, true, true);',
        repeat_interval => 'FREQ=DAILY;BYHOUR=1;BYMINUTE=0;BYSECOND=0',
        start_date => systimestamp at time zone '0:00',
        comments => 'Daily job to manage partitions on PERCENTILES_HIGH',
        auto_drop => FALSE,
        enabled => TRUE
    );
END;
/
