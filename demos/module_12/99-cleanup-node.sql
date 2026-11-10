-- instance: SQL01, then SQL02 (run it on every node)
-- ci: skip (Windows only)
-- Module 12, cleanup of one node: its subscriptions and publications, the database
-- m12_catalog, the other node registered as a subscriber, the distributor and m12_distribution,
-- and the login of the other node's Agent, after the agents of the node have stopped. Removing
-- a node does not require a quiet topology.
-- Then run 99-cleanup-folder.ps1 on SQL01. Safe to run twice.
--   sqlcmd -S SQL01 -E -C -I -i 99-cleanup-node.sql -v PEER_LOGIN="PACHADATA\SQL02$"
--   sqlcmd -S SQL02 -E -C -I -i 99-cleanup-node.sql -v PEER_LOGIN="PACHADATA\SQL01$"
SET NOCOUNT ON;
USE master;
-- the agents of m12_catalog stop first: a connected Log Reader Agent makes the removal fail
-- with Msg 18752 (measured)
DECLARE @job sysname, @i int = 0;
DECLARE jobs CURSOR LOCAL FAST_FORWARD FOR
    SELECT j.name FROM msdb.dbo.sysjobs AS j JOIN msdb.dbo.sysjobactivity AS ja ON ja.job_id = j.job_id
    WHERE j.name LIKE @@SERVERNAME + N'-m12[_]catalog-%' AND ja.start_execution_date IS NOT NULL
      AND ja.stop_execution_date IS NULL AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);
OPEN jobs; FETCH jobs INTO @job;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_stop_job @job_name = @job;
    FETCH jobs INTO @job;
END;
CLOSE jobs; DEALLOCATE jobs;
WHILE @i < 60 AND EXISTS (
    SELECT 1 FROM msdb.dbo.sysjobs AS j JOIN msdb.dbo.sysjobactivity AS ja ON ja.job_id = j.job_id
    WHERE j.name LIKE @@SERVERNAME + N'-m12[_]catalog-%' AND ja.start_execution_date IS NOT NULL
      AND ja.stop_execution_date IS NULL AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
GO
IF DB_ID(N'm12_catalog') IS NOT NULL
BEGIN
    EXEC (N'USE m12_catalog;
    IF OBJECT_ID(N''dbo.syspublications'') IS NOT NULL
    BEGIN
        DECLARE @p sysname;
        DECLARE pubs CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM dbo.syspublications;
        OPEN pubs; FETCH pubs INTO @p;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sys.sp_dropsubscription @publication = @p, @article = N''all'', @subscriber = N''all'';
            EXEC sys.sp_droppublication @publication = @p;
            FETCH pubs INTO @p;
        END;
        CLOSE pubs; DEALLOCATE pubs;
    END;');
    EXEC sys.sp_replicationdboption @dbname = N'm12_catalog', @optname = N'publish', @value = N'false';
    ALTER DATABASE m12_catalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE m12_catalog;
END;
GO
IF EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1) AND DB_ID(N'm12_distribution') IS NOT NULL
BEGIN
    DECLARE @me sysname = @@SERVERNAME, @s sysname;
    DECLARE subs CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.servers WHERE is_subscriber = 1 AND server_id <> 0;
    OPEN subs; FETCH subs INTO @s;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sys.sp_dropsubscriber @subscriber = @s, @ignore_distributor = 1;
        FETCH subs INTO @s;
    END;
    CLOSE subs; DEALLOCATE subs;
    EXEC sys.sp_dropdistpublisher @publisher = @me;
    EXEC sys.sp_dropdistributiondb @database = N'm12_distribution';
    EXEC sys.sp_dropdistributor;
END;
GO
-- sp_dropsubscriber leaves the remote server entry of the other node behind
DECLARE @s sysname;
DECLARE srv CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.servers WHERE server_id <> 0 AND name IN (N'SQL01', N'SQL02') AND name <> @@SERVERNAME;
OPEN srv; FETCH srv INTO @s;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_dropserver @server = @s;
    FETCH srv INTO @s;
END;
CLOSE srv; DEALLOCATE srv;
GO
IF SUSER_ID(N'$(PEER_LOGIN)') IS NOT NULL DROP LOGIN [$(PEER_LOGIN)];
GO
SELECT name FROM sys.databases WHERE name LIKE N'm12[_]%';
SELECT name, is_distributor, is_subscriber FROM sys.servers WHERE server_id <> 0;
SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'%m12[_]%';
SELECT name FROM sys.server_principals WHERE name = N'$(PEER_LOGIN)';
EXEC sys.sp_get_distributor;
