-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.2: the first synchronization of each centre, which applies the snapshot.
--   sqlcmd -S SQL01 -E -C -I -i 04-first-sync.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille';
EXEC dbo.m11_sync @subscriber_db = N'm11_geneve';
