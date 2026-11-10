-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, insert conflict: head office creates another session with the same key, then Lille synchronizes.
--   sqlcmd -S SQL01 -E -C -I -i 13-conflict-insert-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
INSERT Training.Session (SessionId, CentreCode, CourseTitle, StartDate, Room, Seats)
VALUES (2001, 'GEN', 'Peer-to-peer replication', '2027-01-18', 'Room 1', 12);
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
SELECT SessionId, CentreCode, CourseTitle FROM Training.Session WHERE SessionId = 2001;
SELECT a.name AS article, i.conflict_type, i.reason_code, LEFT(i.reason_text, 200) AS reason_text,
       i.origin_datasource, i.MSrepl_create_time
FROM dbo.MSmerge_conflicts_info AS i JOIN dbo.sysmergearticles AS a ON a.nickname = i.tablenick
ORDER BY i.MSrepl_create_time;
SELECT TOP (6) h.time, LEFT(h.comments, 160) AS comments
FROM m11_distribution.dbo.MSmerge_history AS h ORDER BY h.time DESC;
