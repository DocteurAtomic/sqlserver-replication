-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run 05-roundtrip-centre.sql on the subscriber first)
-- Clip 11.2: head office moves a Lille session to another room, then each centre
-- synchronizes: Lille uploads its insert and downloads the update, Geneva downloads both.
--   sqlcmd -S SQL01 -E -C -I -i 06-roundtrip-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
UPDATE Training.Session SET Room = 'Room 7' WHERE SessionId = 1001;
SELECT COUNT(*) AS changes_noted FROM dbo.MSmerge_contents;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
EXEC dbo.m11_sync @subscriber_db = N'm11_geneve';
SELECT AttendanceId, SessionId, TraineeName FROM Training.Attendance
WHERE TraineeName = 'Ines Garnier';
SELECT TOP (4) a.subscriber_db, h.time, LEFT(h.comments, 110) AS comments
FROM m11_distribution.dbo.MSmerge_history AS h
JOIN m11_distribution.dbo.MSmerge_agents AS a ON a.id = h.agent_id
ORDER BY h.time DESC;
