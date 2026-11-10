-- instance: SQL01, then SQL02 (each node restarts its own Distribution Agent)
-- ci: skip (Windows only: run it after 10 and 11)
-- Clip 12.2: the link comes back. The Distribution Agent of m12_pubCourse is started again and
-- meets the change of the other node on a row that changed here too. The script waits for the
-- agent's error or for a delivered change (one minute at most), then reads the price here and
-- the last errors of the local Distributor.
--   sqlcmd -S SQL01 -E -C -I -i 12-reconnect.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname, @agent int, @start datetime = GETDATE(), @i int = 0;
SELECT @job = name, @agent = id FROM m12_distribution.dbo.MSdistribution_agents
WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog';
EXEC msdb.dbo.sp_start_job @job_name = @job;
WHILE @i < 120 AND NOT EXISTS (
    SELECT 1 FROM m12_distribution.dbo.MSdistribution_history
    WHERE agent_id = @agent AND time >= @start AND (runstatus = 6 OR delivered_commands > 0))
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT @@SERVERNAME AS node, CourseId, Price FROM Catalog.Course WHERE CourseId = 4;
SELECT TOP (3) runstatus, LEFT(comments, 160) AS comments FROM m12_distribution.dbo.MSdistribution_history
WHERE agent_id = @agent AND time >= @start ORDER BY time DESC, timestamp DESC;
SELECT TOP (2) error_code, error_text FROM m12_distribution.dbo.MSrepl_errors
WHERE time >= @start ORDER BY time DESC, id DESC;
