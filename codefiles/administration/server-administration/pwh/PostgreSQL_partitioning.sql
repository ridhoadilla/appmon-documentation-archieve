-- AppMon PostgreSQL partitioning script
-------------------------------------------
-- execute this file as the AppMon user (or you have to change the owner of the new tables/functions/etc afterwards)
--
-- you have to specifiy the retention time for the high resolution data in the first function below It must match the AppMon server, default is 14 days.
-- in the same function, you can choose a different value for the percentiles retention time.
--
-- the existing high resolution data and percentiles data are backed up into *_old_data tables. These
--     two tables may be migrated using the "migrate_data(tablename)" function, or by any other means. This function can run for a very long time.
--
-- before executing the script, disconnect the AppMon server from the pwh
--
-- after executing this file, there will be a function called "dynatrace_partitioning_daily_job". You need to set up a daily job (crontab, pgAgent, Windows Scheduler, dt scheduler, ...) to run this function.
--     it should run before the aging task (default 02:00 AM), I suggest 01:00 AM or so.
--     As an example, I have a crontab entry that executes the following bash script everyday at 01:15 AM:
--     	  export PGPASSWORD=<dbuser password>
--     	  psql -U <dynatrace dbuser> -d <dynatrace dbname> -a -f /var/lib/postgresql/scripts/daily_partitioning_job.sql
--     and the file daily_partitioning_job.sql simply contains "select dynatrace_partitioning_daily_job();"
--     note that this function should be run as the AppMon user, or you have to change the owner afterwards
--
-- the final set-up should therefore include (for both tables, 'measurement_high' and 'percentiles_high'):
--     - a master table with rules for the sub tables
--     - sub tables for at least the high_retention time plus 7 days into the future (with names like 'measurement_high_2016-03-07')
--     - 8 auxiliary functions
--     - an externally scheduled task that executes "dynatrace_partitioning_daily_job" daily
--     - two back-up tables 'measurement_high_old_data' and 'percentiles_high_old_data' with the existing high resolution data
--
-- after all this, you need to check the flag "Manually manage deletion of high resolution data" in the Server Settings -> Performance Warhouse -> Storage Management dialog in the AppMon client.
--
-- now you may reconnect the AppMon server and start with the migration of the old high resolution data (if desired)



-- set the correct value for the high resolution retention time in days in the following function:
create or replace function high_retention_time(table_name text) returns integer as
$definition$
select case
    when table_name='measurement_high' then 14::integer -- this value must match the one selected as retention time in the AppMon client
    when table_name='percentiles_high' then 14::integer -- you can choose this value freely, it will be the retention time for percentile values in days
  end;
$definition$
language sql immutable;

-- a 7 day buffer to create new partitions and drop older ones
create or replace function buffer_time() returns integer as
$$select 7::integer$$ language sql immutable;

-- auxiliary date conversion function:
create or replace function f_dbdate2javalong(day date) returns bigint as
$definition$
declare
begin
	return extract(epoch from day) * 1000;
end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- creates a partition (i.e. a table that inherits from the given table_name)
-- together with the necessary rule (as we're doing bulk inserts)
create or replace function create_partition(table_name text, day date) returns void as
$definition$
declare
	start_date date;
	end_date date;
	partition_name text;
begin
	start_date := day;
	end_date := start_date::timestamp + interval '1 day';
	partition_name := table_name||'_'||day;
	-- create the new partition (or leave the old one untouched)
	execute 'create table if not exists ' || quote_ident(partition_name) ||
		    ' (check ( timestamp >= ' || f_dbdate2javalong(start_date) ||
		               'and timestamp < ' || f_dbdate2javalong(end_date) ||
		            '),
		       constraint' ||  quote_ident('pk_' || partition_name) || ' PRIMARY KEY (measure_id,timestamp)
		      ) inherits (' || table_name ||
		                ')';

	-- create the actual partitioning rule
	execute 'create or replace rule ' || quote_ident('rule_' || partition_name) || 'as
	on insert to '||table_name ||' where
		(timestamp >= '||f_dbdate2javalong(start_date)||' and timestamp < '||f_dbdate2javalong(end_date)||')
	do instead
		insert into '||quote_ident(partition_name)||' values (new.*)';

	end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- drops the partition for the given table_name and day
create or replace function drop_partition(table_name text, day date) returns void as
$definition$
declare
	partition_name text;
begin
	partition_name := table_name||'_'||day;
	execute 'drop table if exists ' || quote_ident(partition_name) || 'cascade';
end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- generates partitions for today - high_retention_time days until today + buffer_time days
create or replace function init_partitions(table_name text) returns void as
$definition$
declare
	aday date;
begin
for i in -high_retention_time(table_name)..buffer_time() loop
	aday := (now() + i * interval '1 day');
	perform create_partition(table_name, aday);
end loop;
end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- drop earliest partitions, create a new one buffer_time days in the future
create or replace function slide_window(table_name text) returns void as
$definition$
declare
	aday date;
begin
for i in 1..buffer_time() loop
	aday := now() + i * interval '1 day';
	perform create_partition(table_name, aday); -- create partitions for the whole week (in case something failed on a previous day)
end loop;
for i in 1..buffer_time() loop
	aday := now() - (high_retention_time(table_name)+i) * interval '1 day'; -- drop the (theoretically) earliest partition (and, in case some days were left out, try to drop buffer_time() days prior as well)
	perform drop_partition(table_name, aday);
end loop;
end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- slides the window for the two partitioned tables
create or replace function dynatrace_partitioning_daily_job() returns void as
$definition$
declare
begin
	perform slide_window('measurement_high');
	perform slide_window('percentiles_high');
end;
$definition$
language plpgsql;

----------------------------------------------------------------------------
-- the following lines set up the tables initially

-- rename existing tables
alter table measurement_high rename to measurement_high_old_data;
alter index if exists pk_measurement_high rename to pk_measurement_high_old_data;


alter table percentiles_high rename to percentiles_high_old_data;
alter index if exists pk_percentiles_high rename to pk_percentiles_high_old_data;


-- create new master tables (without indices and keys etc)
create table measurement_high (
  measure_id integer not null,
  timestamp bigint not null,
  minvalue float8,
  maxvalue float8,
  sumvalue float8,
  countvalue bigint,
  CONSTRAINT pk_measurement_high PRIMARY KEY (measure_id, "timestamp")
);

create table percentiles_high (
  measure_id integer not null,
  timestamp bigint not null,
  pquantile float8,
  markercount smallint,
  obscount integer,
  maximum float8,
  minimum float8,
  outliercount integer,
  markerpos0 integer,
  markerpos1 integer,
  markerpos2 integer,
  markerpos3 integer,
  markerpos4 integer,
  markerpos5 integer,
  markerpos6 integer,
  markerpos7 integer,
  markerpos8 integer,
  markerpos9 integer,
  markerpos10 integer,
  markerpos11 integer,
  markerpos12 integer,
  markerpos13 integer,
  markerpos14 integer,
  markerpos15 integer,
  markerpos16 integer,
  markerpos17 integer,
  markerpos18 integer,
  markerpos19 integer,
  markerpos20 integer,
  markerpos21 integer,
  markerpos22 integer,
  markerpos23 integer,
  markerpos24 integer,
  markerpos25 integer,
  markerpos26 integer,
  markerpos27 integer,
  markerpos28 integer,
  markerheight0 float8,
  markerheight1 float8,
  markerheight2 float8,
  markerheight3 float8,
  markerheight4 float8,
  markerheight5 float8,
  markerheight6 float8,
  markerheight7 float8,
  markerheight8 float8,
  markerheight9 float8,
  markerheight10 float8,
  markerheight11 float8,
  markerheight12 float8,
  markerheight13 float8,
  markerheight14 float8,
  markerheight15 float8,
  markerheight16 float8,
  markerheight17 float8,
  markerheight18 float8,
  markerheight19 float8,
  markerheight20 float8,
  markerheight21 float8,
  markerheight22 float8,
  markerheight23 float8,
  markerheight24 float8,
  markerheight25 float8,
  markerheight26 float8,
  markerheight27 float8,
  markerheight28 float8,
  CONSTRAINT pk_percentiles_high PRIMARY KEY (measure_id, "timestamp")
);

-- create the initial partitions
select init_partitions('measurement_high');
select init_partitions('percentiles_high');

----------------------------------------------------------------------------
-- finally, move old data to the new tables

-- function to migrate exisiting data into new tables:
create or replace function migrate_data(table_name text) returns void as
$definition$
declare
	today timestamp;
	iteration_time timestamp;
begin
select current_date into today;
for i in -high_retention_time(table_name)*24..buffer_time()*24 loop
	iteration_time := today + (i * interval '1 hour');
	execute 'insert into ' || quote_ident(table_name) ||
	       ' select * from ' || quote_ident(table_name || '_old_data') ||
	       ' where ' || quote_ident(table_name || '_old_data') || '.timestamp >= f_dbdate2javalong(''' || iteration_time || ''')
	        and ' || quote_ident(table_name || '_old_data') || '.timestamp < f_dbdate2javalong(''' || iteration_time + interval '1 hour' ||
	       ''')';
end loop;	
end;
$definition$
language plpgsql;

-- execute these statements at your leisure (may run for a very long time)

-- create index concurrently if not exists mh_old_timestamp on measurement_high_old_data ("timestamp");
-- select migrate_data('measurement_high');

-- create index concurrently if not exists ph_old_timestamp on percentiles_high_old_data ("timestamp");
-- select migrate_data('percentiles_high');
