-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 23-subscribe-by-centre.sql)
-- Clip 11.4: head office moves session 1004 from Lille to Geneva. The row leaves the Lille
-- partition with its attendance lines, and enters the Geneva one.
--   sqlcmd -S SQL01 -E -C -I -i 25-move-session.sql
SET NOCOUNT ON;
USE m11_pacha;
UPDATE Training.Session SET CentreCode = 'GEN' WHERE SessionId = 1004;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille', @publication = N'm11_pubByCentre';
EXEC dbo.m11_sync @subscriber_db = N'm11_geneve', @publication = N'm11_pubByCentre';
