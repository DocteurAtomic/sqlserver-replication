-- instance: SQL01, then SQL02 (each node restarts its own Distribution Agent)
-- ci: skip (Windows only: run 13-continue-onconflict.sql on both nodes first)
-- Clip 12.2: the Distribution Agent of m12_pubCourse is restarted, so that it reads the new
-- setting. It waits for the agent to deliver or fail (one minute at most), then reads the price
-- and the conflict table of Course: the row of the highest originator ID wins.
--   sqlcmd -S SQL01 -E -C -I -i 14-restart-course.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname, @agent int, @start datetime, @i int = 0;
SELECT @job = name, @agent = id FROM m12_distribution.dbo.MSdistribution_agents
WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog';
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobactivity AS ja JOIN msdb.dbo.sysjobs AS j ON j.job_id = ja.job_id
           WHERE j.name = @job AND ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL
             AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
BEGIN
    EXEC msdb.dbo.sp_stop_job @job_name = @job;
    WHILE @i < 60 AND EXISTS (SELECT 1 FROM msdb.dbo.sysjobactivity AS ja JOIN msdb.dbo.sysjobs AS j ON j.job_id = ja.job_id
           WHERE j.name = @job AND ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL
             AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
    BEGIN WAITFOR DELAY '00:00:00.500'; SET @i += 1; END;
END;
SET @start = GETDATE(); SET @i = 0;
EXEC msdb.dbo.sp_start_job @job_name = @job;
WHILE @i < 120 AND NOT EXISTS (
    SELECT 1 FROM m12_distribution.dbo.MSdistribution_history
    WHERE agent_id = @agent AND time >= @start AND (runstatus = 6 OR delivered_commands > 0))
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT @@SERVERNAME AS node, CourseId, Price FROM Catalog.Course WHERE CourseId = 4;
SELECT TOP (2) runstatus, LEFT(comments, 120) AS comments FROM m12_distribution.dbo.MSdistribution_history
WHERE agent_id = @agent AND time >= @start ORDER BY time DESC, timestamp DESC;
SELECT __$originator_id AS originator_id, __$origin_datasource AS origin, __$conflict_type AS conflict_type,
       __$is_winner AS is_winner, CourseId, Price, __$reason_text AS reason_text
FROM dbo.conflict_Catalog_Course ORDER BY __$row_id;
