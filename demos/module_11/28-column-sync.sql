-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run 27-column-centre.sql on the subscriber first)
-- Clip 11.4: head office changes the room of session 1007, Lille synchronizes: the two
-- columns merge into one row, without a conflict.
--   sqlcmd -S SQL01 -E -C -I -i 28-column-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
UPDATE Training.Session SET Room = 'Room 3' WHERE SessionId = 1007;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille', @publication = N'm11_pubByCentre';
SELECT SessionId, Room, Seats FROM Training.Session WHERE SessionId = 1007;
SELECT COUNT(*) AS conflicts_on_1007 FROM dbo.MSmerge_conflict_m11_pubByCentre_Session WHERE SessionId = 1007;
