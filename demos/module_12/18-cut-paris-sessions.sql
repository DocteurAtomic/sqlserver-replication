-- instance: SQL01 (Paris)
-- ci: skip (Windows only: run it after 17-cut-lyon-sessions.sql on SQL02)
-- Clip 12.2, last writer wins: Paris, cut from Lyon too, writes later on the same two
-- sessions: 16 seats on session 110, 8 seats on session 121, which Lyon has deleted.
--   sqlcmd -S SQL01 -E -C -I -i 18-cut-paris-sessions.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubSession' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_stop_job @job_name = @job;
UPDATE Catalog.Session SET Seats = 16 WHERE SessionId = 110;
UPDATE Catalog.Session SET Seats = 8 WHERE SessionId = 121;
SELECT @@SERVERNAME AS node, SYSUTCDATETIME() AS utc_time, SessionId, Seats
FROM Catalog.Session WHERE SessionId IN (110, 121);
