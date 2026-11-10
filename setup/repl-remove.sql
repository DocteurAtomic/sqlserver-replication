-- Run by repl-remove.sh on each instance, distributor first, with N set to the instance name.
-- Removes every replication object of the instance without asking the other instances, so
-- that it works whatever state a module or an exercise left. It drops no database except
-- distribution: the databases a module creates are dropped by its own 99-cleanup.
-- Measured on 10 November 2026, the order matters:
--   1. the agent jobs go first: while a Log Reader Agent is connected to a published
--      database, sp_removedbreplication fails on the publisher with Msg 18752;
--   2. the distribution database is dropped once no session uses it (Msg 924 otherwise);
--   3. then the publishing and subscribing databases, then the distributor registration.
SET NOCOUNT ON;
DECLARE @name sysname, @q nvarchar(max);

-- 1. Agent jobs (snapshot, log reader, distribution, merge, queue reader), stopped then dropped.
DECLARE jobs CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.name FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE c.name IN (N'REPL-Snapshot', N'REPL-LogReader', N'REPL-Distribution', N'REPL-Merge', N'REPL-QueueReader');
OPEN jobs; FETCH jobs INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT N'$(N): dropping agent job ' + @name;
    -- sp_stop_job on a job that is not running raises an Agent error that sqlcmd -b counts.
    IF EXISTS (SELECT * FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
               WHERE j.name = @name AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
                 AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
        EXEC msdb.dbo.sp_stop_job @job_name = @name;
    EXEC msdb.dbo.sp_delete_job @job_name = @name;
    FETCH jobs INTO @name;
END;
CLOSE jobs; DEALLOCATE jobs;

-- 2. Distributor side: registered publishers, distribution databases, the distributor itself.
IF EXISTS (SELECT * FROM sys.databases WHERE is_distributor = 1)
BEGIN
    IF OBJECT_ID(N'msdb.dbo.MSdistpublishers') IS NOT NULL
    BEGIN
        DECLARE pubs CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM msdb.dbo.MSdistpublishers;
        OPEN pubs; FETCH pubs INTO @name;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            PRINT N'$(N): dropping publisher ' + @name + N' from the distributor';
            EXEC sys.sp_dropdistpublisher @publisher = @name, @no_checks = 1, @ignore_distributor = 1;
            FETCH pubs INTO @name;
        END;
        CLOSE pubs; DEALLOCATE pubs;
    END;
    DECLARE ddbs CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE is_distributor = 1;
    OPEN ddbs; FETCH ddbs INTO @name;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Sessions still in the database (an agent ending, a monitor) would make the drop fail.
        SET @q = N'';
        SELECT @q += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';'
        FROM sys.dm_exec_sessions WHERE database_id = DB_ID(@name) AND session_id <> @@SPID;
        EXEC (@q);
        IF (SELECT user_access FROM sys.databases WHERE name = @name) <> 0
        BEGIN
            SET @q = N'ALTER DATABASE ' + QUOTENAME(@name) + N' SET MULTI_USER WITH ROLLBACK IMMEDIATE;';
            EXEC (@q);
        END;
        PRINT N'$(N): dropping distribution database ' + @name;
        EXEC sys.sp_dropdistributiondb @database = @name;
        FETCH ddbs INTO @name;
    END;
    CLOSE ddbs; DEALLOCATE ddbs;
END;

-- 3. Published and subscribed databases.
DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE (is_published = 1 OR is_merge_published = 1 OR is_subscribed = 1) AND state_desc = N'ONLINE';
OPEN dbs; FETCH dbs INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT N'$(N): removing replication from database ' + @name;
    EXEC sys.sp_removedbreplication @dbname = @name, @type = N'both';
    FETCH dbs INTO @name;
END;
CLOSE dbs; DEALLOCATE dbs;

-- 4. The distributor registration (publisher side, and what is left on the distributor).
DECLARE @d TABLE (installed int, distribution_server sysname NULL, distribution_db_installed int,
                  is_distribution_publisher int, has_remote_distribution_publisher int);
INSERT @d EXEC sys.sp_get_distributor;
IF (SELECT installed FROM @d) = 1
BEGIN
    PRINT N'$(N): dropping the distributor registration';
    EXEC sys.sp_dropdistributor @no_checks = 1, @ignore_distributor = 1;
END;

-- 5. Replication jobs left: pull subscription agents, cleanup jobs.
DECLARE left_jobs CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.name FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id WHERE c.name LIKE N'REPL-%';
OPEN left_jobs; FETCH left_jobs INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT N'$(N): dropping job ' + @name;
    -- sp_stop_job on a job that is not running raises an Agent error that sqlcmd -b counts.
    IF EXISTS (SELECT * FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
               WHERE j.name = @name AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
                 AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
        EXEC msdb.dbo.sp_stop_job @job_name = @name;
    EXEC msdb.dbo.sp_delete_job @job_name = @name;
    FETCH left_jobs INTO @name;
END;
CLOSE left_jobs; DEALLOCATE left_jobs;

-- 6. Remote server entries that sp_addsubscription leaves for a subscriber (not linked, no flag).
DECLARE left_servers CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.servers
    WHERE server_id > 0 AND is_linked = 0 AND name LIKE N'RPLLAB%' AND name <> @@SERVERNAME;
OPEN left_servers; FETCH left_servers INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT N'$(N): dropping remote server ' + @name;
    EXEC sys.sp_dropserver @server = @name, @droplogins = N'droplogins';
    FETCH left_servers INTO @name;
END;
CLOSE left_servers; DEALLOCATE left_servers;
