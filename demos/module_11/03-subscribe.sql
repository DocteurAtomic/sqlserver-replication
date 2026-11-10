-- instance: SQL01 (publisher and distributor: push subscriptions, agents on SQL01)
-- ci: skip (Windows only: needs the snapshot of 02-snapshot.sql)
-- Clip 11.2: two push subscriptions, one per centre, both on the subscriber instance, a Merge
-- Agent per subscription that runs on demand, and dbo.m11_sync, which starts the agent of one
-- subscription and waits for the end of its session (three minutes at most).
--   sqlcmd -S SQL01 -E -C -I -i 03-subscribe.sql -v SUBSCRIBER=SQL02
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_addmergesubscription @publication = N'm11_pubCentres', @subscriber = N'$(SUBSCRIBER)',
     @subscriber_db = N'm11_lille', @subscription_type = N'push';
EXEC sys.sp_addmergepushsubscription_agent @publication = N'm11_pubCentres',
     @subscriber = N'$(SUBSCRIBER)', @subscriber_db = N'm11_lille',
     @subscriber_security_mode = 1, @frequency_type = 2;
EXEC sys.sp_addmergesubscription @publication = N'm11_pubCentres', @subscriber = N'$(SUBSCRIBER)',
     @subscriber_db = N'm11_geneve', @subscription_type = N'push';
EXEC sys.sp_addmergepushsubscription_agent @publication = N'm11_pubCentres',
     @subscriber = N'$(SUBSCRIBER)', @subscriber_db = N'm11_geneve',
     @subscriber_security_mode = 1, @frequency_type = 2;
GO
CREATE OR ALTER PROCEDURE dbo.m11_sync @subscriber_db sysname, @publication sysname = N'm11_pubCentres'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @job sysname, @agent int, @start datetime = GETDATE(), @status int = 0, @i int = 0;
    SELECT @job = j.name, @agent = a.id
    FROM m11_distribution.dbo.MSmerge_agents AS a
    JOIN msdb.dbo.sysjobs AS j ON j.job_id = CONVERT(uniqueidentifier, a.job_id)
    WHERE a.subscriber_db = @subscriber_db AND a.publication = @publication;
    EXEC msdb.dbo.sp_start_job @job_name = @job;
    WHILE @status NOT IN (2, 6) AND @i < 180
    BEGIN
        WAITFOR DELAY '00:00:01';
        SET @i += 1;
        SELECT TOP (1) @status = runstatus FROM m11_distribution.dbo.MSmerge_sessions
        WHERE agent_id = @agent AND start_time >= DATEADD(SECOND, -2, @start)
        ORDER BY session_id DESC;
    END;
    SELECT TOP (1) @subscriber_db AS subscriber_db,
           CASE runstatus WHEN 2 THEN 'succeeded' WHEN 6 THEN 'failed' ELSE 'still running' END AS result,
           duration, upload_inserts, upload_updates, upload_deletes, upload_conflicts,
           download_inserts, download_updates, download_deletes, download_conflicts
    FROM m11_distribution.dbo.MSmerge_sessions
    WHERE agent_id = @agent ORDER BY session_id DESC;
END;
GO
SELECT p.name AS publication, s.subscriber_server, s.db_name, s.subscription_type,
       s.subscriber_type, s.priority
FROM dbo.sysmergesubscriptions AS s
JOIN dbo.sysmergepublications AS p ON p.pubid = s.pubid
WHERE s.db_name <> DB_NAME();
SELECT j.name AS job_name FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.syscategories AS c ON c.category_id = j.category_id
WHERE c.name LIKE N'REPL%' ORDER BY j.name;
