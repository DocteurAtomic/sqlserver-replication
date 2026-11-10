-- instance: SQL02 (Lyon)
-- ci: skip (Windows only)
-- Clip 12.2, last writer wins: the link from Lyon to Paris is cut for m12_pubSession. Lyon
-- changes the seats of session 110 and cancels session 121.
--   sqlcmd -S SQL02 -E -C -I -i 17-cut-lyon-sessions.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubSession' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_stop_job @job_name = @job;
UPDATE Catalog.Session SET Seats = 14 WHERE SessionId = 110;
DELETE Catalog.Session WHERE SessionId = 121;
SELECT @@SERVERNAME AS node, SYSUTCDATETIME() AS utc_time, SessionId, Seats
FROM Catalog.Session WHERE SessionId IN (110, 121);
