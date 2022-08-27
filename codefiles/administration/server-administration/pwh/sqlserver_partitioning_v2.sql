-- This T-SQL scripts enables Partitioning in an AppMon PWH database for the tables
--   MEASUREMENT_HIGH, PERCENTILES_HIGH
-- Feature-set/description of our new partitioning implementation V2:
--   Fully T-SQL based partition maintenance implementation, ready to be scheduled in a daily SQL Server job
--   Minimized SQL Server lock contention to ensure concurrency between the daily partitioning maintenance job and regular operations
--   Zero data movement while adding new empty daily partition ranges
--   Support for switching/purging out data with a configurable retention time in days
--   Ready to be used on existing MEASUREMENT_HIGH, PERCENTILES_HIGH data. No need to start with an empty database
--   Operates on the [PRIMARY] file group only!
--   The script does not include code to schedule a daily SQL Server job.
-- Usage:
--   Before script execution, make sure to create a backup of the database (just in case)
--   Disconnect the AppMon server from the PWH
--   Replace <database> with the real name of the AppMon database
--   Search for a local variable called @highRetentionTimeInDays and adapt the value (in days) according to the High Resolution Duration configuration for the Performance Warehouse in the AppMon client. They MUST match!
--   Adapt the retention time while calling the stored procedure. Default is 14 days. This MUST match with the configured high retention time as well!
--   Preferable, the script should be run with the customer DBA and a member of the PWH R&D team
--   Check, if the data type of the countvalue field in the additional/new table MEASUREMENT_HIGH_PARTITION_SWITCH_OUT is exactly the same as in MEASUREMENT_HIGH.
--   The last step to finish up the partitioning setup is to enable the option 'Manually manage deletion of high resolution data (for partitioning)' in PWH storage management.


USE <database> -- ADAPT THIS PROPERLY. Use the AppMon PWH database here!
GO

-- drop partition scheme ps_dynatrace
-- drop partition function pf_dynatrace

IF OBJECT_ID('dbo.F_DBDATE2JAVALONG') IS NOT NULL
BEGIN
  DROP FUNCTION F_DBDATE2JAVALONG
END
GO

CREATE FUNCTION F_DBDATE2JAVALONG
(
  @pDBDate DATETIME
)
RETURNS BIGINT
AS
BEGIN
  RETURN (CAST(DATEDIFF(SECOND,{d '1970-01-01'}, @pDBDate) AS BIGINT) * 1000)
END
GO

IF OBJECT_ID('dbo.F_JAVALONG2DBDATE') IS NOT NULL
BEGIN
  DROP FUNCTION F_JAVALONG2DBDATE
END
GO

CREATE FUNCTION F_JAVALONG2DBDATE
(
  @pJavaLong BIGINT
)
RETURNS DATETIME
AS
BEGIN
  RETURN (DATEADD(SECOND, @pJavaLong / 1000, {d '1970-01-01'}))
END
GO

DECLARE @highRetentionTimeInDays integer = 14; -- ADAPT THIS PROPERLY !!!
DECLARE @maxDayOffset integer = 7; -- We want to have (empty) partitions for maxDayOffset days in the future. DON'T CHANGE this
DECLARE @daysFrom integer = - (@highRetentionTimeInDays + 2);
DECLARE @daysTo integer = @maxDayOffset;
DECLARE @currentPartition BIGINT;
DECLARE @currentPartitionAsString varchar(max);
DECLARE @currentUTCDate Date = cast(GETUTCDATE() as Date);
DECLARE @listOfRangeValues varchar(max) = NULL; -- Don't change that default value !!!
WHILE (@daysFrom <= @daysTo) -- Usually from -16 to 7
BEGIN
	SET @currentPartition = dbo.F_DBDATE2JAVALONG(DATEADD(DAY, @daysFrom, @currentUTCDate));
	SET @currentPartitionAsString = cast(@currentPartition as varchar(max));
	IF (@listOfRangeValues IS NULL)
		SET @listOfRangeValues = @currentPartitionAsString;
	ELSE
		SET @listOfRangeValues = @listOfRangeValues + ', ' + @currentPartitionAsString;

	SET @daysFrom = @daysFrom + 1;
END
DECLARE @partitionFunctionDDL varchar(max) = 'CREATE PARTITION FUNCTION PF_DYNATRACE(BIGINT) AS RANGE RIGHT FOR VALUES (' + @listOfRangeValues + ')';
EXEC (@partitionFunctionDDL);
CREATE PARTITION SCHEME PS_DYNATRACE AS PARTITION PF_DYNATRACE ALL TO ([PRIMARY])
GO

IF OBJECT_ID('dbo.MEASUREMENT_HIGH_PARTITION_SWITCH_OUT') IS NOT NULL
BEGIN
  DROP TABLE MEASUREMENT_HIGH_PARTITION_SWITCH_OUT
END
GO

-- to be used as auxiliary table for switching out old MEASUREMENT_HIGH partitions
CREATE TABLE MEASUREMENT_HIGH_PARTITION_SWITCH_OUT (
    measure_id INTEGER,
    timestamp bigint,
    minvalue float,
    maxvalue float,
    sumvalue float,
    countvalue BIGINT, -- Make sure that the used data type is identically as in MEASUREMENT_HIGH !!!
    CONSTRAINT PK_MEASUREMENT_HIGH_PARTITION_SWITCH_OUT PRIMARY KEY CLUSTERED
    (
        measure_id ASC,
        timestamp ASC
    )
)
GO

IF OBJECT_ID('dbo.PERCENTILES_HIGH_PARTITION_SWITCH_OUT') IS NOT NULL
BEGIN
  DROP TABLE PERCENTILES_HIGH_PARTITION_SWITCH_OUT
END
GO


-- to be used as auxiliary table for switching out old PERCENTILES_HIGH partitions
CREATE TABLE PERCENTILES_HIGH_PARTITION_SWITCH_OUT (
  measure_id INTEGER,
  timestamp bigint,
  pQuantile double precision,
  markercount TINYINT,
  obscount INTEGER,
  maximum double precision,
  minimum double precision,
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
  markerheight0 double precision,
  markerheight1 double precision,
  markerheight2 double precision,
  markerheight3 double precision,
  markerheight4 double precision,
  markerheight5 double precision,
  markerheight6 double precision,
  markerheight7 double precision,
  markerheight8 double precision,
  markerheight9 double precision,
  markerheight10 double precision,
  markerheight11 double precision,
  markerheight12 double precision,
  markerheight13 double precision,
  markerheight14 double precision,
  markerheight15 double precision,
  markerheight16 double precision,
  markerheight17 double precision,
  markerheight18 double precision,
  markerheight19 double precision,
  markerheight20 double precision,
  markerheight21 double precision,
  markerheight22 double precision,
  markerheight23 double precision,
  markerheight24 double precision,
  markerheight25 double precision,
  markerheight26 double precision,
  markerheight27 double precision,
  markerheight28 double precision,
  CONSTRAINT PK_PERCENTILES_HIGH_PARTITION_SWITCH_OUT PRIMARY KEY CLUSTERED
  (
	measure_id ASC,
	timestamp ASC
   )
)
GO

IF OBJECT_ID('P_PROCESS_DAILY_PARTITIONS') IS NOT NULL
BEGIN
  DROP PROCEDURE P_PROCESS_DAILY_PARTITIONS
END
GO

CREATE PROCEDURE P_PROCESS_DAILY_PARTITIONS (
	@retentionInDays integer = 14 -- Retention MEASUREMENT_HIGH period in days
	, @addNewEmptyPartitions bit = true -- Add new empty partitions?
	, @maxNewEmptyDayOffset integer = 7 -- Max number of empty future partitions
)
AS
BEGIN
	SET NOCOUNT ON
	declare @partitionFunctionName sysname = N'PF_DYNATRACE';
	declare @waitForDelay char(8) = '00:00:10'; -- Wait 10 seconds until next retry iteration in case of failed statements
	declare @splitRetry integer = 5; -- Number of retries for the SPLIT use case
	declare @purgeRetry integer = 5; -- Number of retries for the PURGE/SWITCH OUT use case
	declare @currentUTCDate Date = cast(GETUTCDATE() as Date);
	declare @ErrorMessage nvarchar(max), @ErrorSeverity int, @ErrorState int;

	IF (@addNewEmptyPartitions = 1)
	BEGIN
		-- Add new empty ranges
		declare @latestRangeValue bigint = cast(
			(
				select top 1 [value] from
					sys.partition_range_values
				where
					function_id = (
						select function_id from
							sys.partition_functions
						where
							name = @partitionFunctionName
					)
				order by boundary_id DESC
			) as bigint
		);

		declare @latestDay Date = coalesce(cast(dbo.F_JAVALONG2DBDATE(@latestRangeValue) as date), DATEADD(DAY, -1, @currentUTCDate));
		declare @latestDayPlusOffset Date = DATEADD(DAY, @maxNewEmptyDayOffset, @currentUTCDate);
		declare @dayDiff integer = DATEDIFF(DAY, @latestDay, @latestDayPlusOffset);
		declare @i integer = 1;
		declare @doSplitContinue bit = 1;
		WHILE (@dayDiff > 0) AND (@doSplitContinue = 1)
		BEGIN
			declare @day Date = DATEADD(DAY, @i, @latestDay);

			declare @doSplitRetryContinue bit = 1;
			WHILE (@splitRetry > 0) AND (@doSplitRetryContinue = 1)
			BEGIN
				BEGIN TRY
					BEGIN TRANSACTION;

					ALTER PARTITION SCHEME PS_DYNATRACE NEXT USED [PRIMARY];
					ALTER PARTITION FUNCTION PF_DYNATRACE() SPLIT RANGE (dbo.F_DBDATE2JAVALONG(@day));

					IF (XACT_STATE() = 1)
					BEGIN
						COMMIT TRANSACTION;
					END

					SET @doSplitRetryContinue = 0; -- succesful => exit retry loop
				END TRY
				BEGIN CATCH
					SET @doSplitRetryContinue = 1;
					SET @splitRetry = @splitRetry - 1; -- Decrease retry counter
					IF (XACT_STATE() <> 0)
					BEGIN
						ROLLBACK TRANSACTION;
					END;
					IF (@splitRetry <= 0)
					BEGIN
						SELECT @ErrorMessage = ERROR_MESSAGE() + ' Error while SPLITTING: Line ' + cast(ERROR_LINE() as nvarchar(10)), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = ERROR_STATE();
						RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
					END;

					WAITFOR DELAY @waitForDelay; -- Wait X seconds until next retry iteration
				END CATCH
			END

			IF (@doSplitRetryContinue = 0)
			BEGIN
				-- Successful
				SET @doSplitContinue = 1;
				SET @dayDiff = @dayDiff - 1;
				SET @i = @i + 1;
			END
			ELSE
			BEGIN
				-- Consecutive partition creation failed => EXIT loop
				SET @doSplitContinue = 0;
			END
		END
		-- New ranges added
	END

	-- Purge partitions out which are older than @retentionInDays
	declare @rangeValue bigint;
	BEGIN TRY
		declare c cursor FORWARD_ONLY STATIC READ_ONLY for
			select cast([value] as bigint) from
					sys.partition_range_values
				where
					function_id = (
						select function_id from
							sys.partition_functions
						where
							name = @partitionFunctionName
					)
					and cast([value] as bigint) < dbo.F_DBDATE2JAVALONG(DATEADD(DAY, - @retentionInDays, @currentUTCDate))
				order by boundary_id ASC;
		OPEN c;
		FETCH NEXT FROM c INTO @rangeValue;
		declare @doPurgeContinue bit = 1;
		WHILE (@@FETCH_STATUS = 0) AND (@doPurgeContinue = 1)
		BEGIN
			declare @doPurgeRetryContinue bit = 1;
			WHILE (@purgeRetry > 0) AND (@doPurgeRetryContinue = 1)
			BEGIN
				BEGIN TRY
					BEGIN TRANSACTION;

					ALTER TABLE measurement_high SWITCH PARTITION 1 TO measurement_high_partition_switch_out;
					TRUNCATE TABLE MEASUREMENT_HIGH_PARTITION_SWITCH_OUT;
					ALTER TABLE percentiles_high SWITCH PARTITION 1 TO percentiles_high_partition_switch_out;
					TRUNCATE TABLE PERCENTILES_HIGH_PARTITION_SWITCH_OUT;
					ALTER PARTITION FUNCTION PF_DYNATRACE() MERGE RANGE (@rangeValue);

					IF (XACT_STATE() = 1)
					BEGIN
						COMMIT TRANSACTION;
					END

					SET @doPurgeRetryContinue = 0; -- succesful => exit retry loop
				END TRY
				BEGIN CATCH
					SET @doPurgeRetryContinue = 1;
					SET @purgeRetry = @purgeRetry - 1; -- Decrease retry counter
					IF (XACT_STATE() <> 0)
					BEGIN
						ROLLBACK TRANSACTION;
					END;
					IF (@purgeRetry <= 0)
					BEGIN
						SELECT @ErrorMessage = ERROR_MESSAGE() + ' Error while PURGING: Line ' + cast(ERROR_LINE() as nvarchar(10)), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = ERROR_STATE();
						RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
					END;

					WAITFOR DELAY @waitForDelay; -- Wait X seconds until next retry iteration
				END CATCH
			END

			IF (@doPurgeRetryContinue = 0)
			BEGIN
				-- Successful
				SET @doPurgeContinue = 1;
				FETCH NEXT FROM c INTO @rangeValue;
			END
			ELSE
			BEGIN
				-- Consecutive purge failed => EXIT loop
				SET @doPurgeContinue = 0;
			END

		END
		CLOSE c;
		DEALLOCATE c;
	END TRY
	BEGIN CATCH
	  -- Failure
	  CLOSE c;
	  DEALLOCATE c;
	  RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState);
	END CATCH
END
GO

/*
-- Example of usage with a measurement high retention time of 14 days

EXECUTE dbo.P_PROCESS_DAILY_PARTITIONS 14
GO

*/

-- Recreate clustered index on MEASUREMENT_HIGH with provided partitioning scheme
CREATE UNIQUE CLUSTERED INDEX PK_MEASUREMENT_HIGH ON measurement_high (measure_id ASC, timestamp ASC) WITH (DROP_EXISTING = ON) ON PS_DYNATRACE(timestamp)
GO

-- Recreate clustered index on PERCENTILES_HIGH with provided partitioning scheme
CREATE UNIQUE CLUSTERED INDEX PK_PERCENTILES_HIGH ON percentiles_high (measure_id ASC, timestamp ASC) WITH (DROP_EXISTING = ON) ON PS_DYNATRACE(timestamp)
GO
