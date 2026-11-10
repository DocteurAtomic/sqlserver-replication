-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, row-level tracking: head office changes another column of the same row, then Lille synchronizes.
--   sqlcmd -S SQL01 -E -C -I -i 09-conflict-row-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
UPDATE Training.Session SET Room = 'Room 5' WHERE SessionId = 1002;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
SELECT SessionId, Room, Seats FROM Training.Session WHERE SessionId = 1002;
SELECT a.name AS article, i.conflict_type, i.reason_code, LEFT(i.reason_text, 150) AS reason_text,
       i.origin_datasource, i.MSrepl_create_time
FROM dbo.MSmerge_conflicts_info AS i JOIN dbo.sysmergearticles AS a ON a.nickname = i.tablenick
ORDER BY i.MSrepl_create_time;
SELECT SessionId, Room, Seats, origin_datasource_id FROM dbo.MSmerge_conflict_m11_pubCentres_Session;
EXEC sys.sp_helpmergearticleconflicts @publication = N'm11_pubCentres';
