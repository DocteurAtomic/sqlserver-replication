-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the snapshot of 22-snapshot-by-centre.sql)
-- Clip 11.4: one push subscription per centre, each with the value HOST_NAME() returns for it
-- (@hostname), then the first synchronization of each.
--   sqlcmd -S SQL01 -E -C -I -i 23-subscribe-by-centre.sql -v SUBSCRIBER=SQL02
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_addmergesubscription @publication = N'm11_pubByCentre', @subscriber = N'$(SUBSCRIBER)',
     @subscriber_db = N'm11_lille', @subscription_type = N'push', @hostname = N'LIL';
EXEC sys.sp_addmergepushsubscription_agent @publication = N'm11_pubByCentre',
     @subscriber = N'$(SUBSCRIBER)', @subscriber_db = N'm11_lille',
     @subscriber_security_mode = 1, @frequency_type = 2;
EXEC sys.sp_addmergesubscription @publication = N'm11_pubByCentre', @subscriber = N'$(SUBSCRIBER)',
     @subscriber_db = N'm11_geneve', @subscription_type = N'push', @hostname = N'GEN';
EXEC sys.sp_addmergepushsubscription_agent @publication = N'm11_pubByCentre',
     @subscriber = N'$(SUBSCRIBER)', @subscriber_db = N'm11_geneve',
     @subscriber_security_mode = 1, @frequency_type = 2;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille', @publication = N'm11_pubByCentre';
EXEC dbo.m11_sync @subscriber_db = N'm11_geneve', @publication = N'm11_pubByCentre';
SELECT s.db_name AS subscriber_db, s.subscriber_type, s.partition_id
FROM dbo.sysmergesubscriptions AS s WHERE s.db_name <> DB_NAME() ORDER BY s.db_name;
SELECT * FROM dbo.MSmerge_partition_groups;
