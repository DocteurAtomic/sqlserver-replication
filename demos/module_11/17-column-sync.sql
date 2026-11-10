-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, column-level tracking: head office changes the room of session 1005, then Lille synchronizes: two columns, no conflict. Then both change the room: a conflict.
--   sqlcmd -S SQL01 -E -C -I -i 17-column-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
UPDATE Training.Session SET Room = 'Room 3' WHERE SessionId = 1005;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
SELECT SessionId, Room, Seats FROM Training.Session WHERE SessionId = 1005;
SELECT COUNT(*) AS conflicts_on_1005 FROM dbo.MSmerge_conflict_m11_pubCentres_Session WHERE SessionId = 1005;
