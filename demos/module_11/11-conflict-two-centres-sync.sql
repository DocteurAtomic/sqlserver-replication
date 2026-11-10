-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, two client subscriptions: Geneva synchronizes first, then Lille; the first change to reach the publisher wins.
--   sqlcmd -S SQL01 -E -C -I -i 11-conflict-two-centres-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC dbo.m11_sync @subscriber_db = N'm11_geneve';
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
SELECT SessionId, Room FROM Training.Session WHERE SessionId = 1004;
SELECT a.name AS article, i.conflict_type, i.reason_code, LEFT(i.reason_text, 150) AS reason_text,
       i.origin_datasource, i.MSrepl_create_time
FROM dbo.MSmerge_conflicts_info AS i JOIN dbo.sysmergearticles AS a ON a.nickname = i.tablenick
ORDER BY i.MSrepl_create_time;
SELECT SessionId, Room, Seats FROM dbo.MSmerge_conflict_m11_pubCentres_Session ORDER BY SessionId;
