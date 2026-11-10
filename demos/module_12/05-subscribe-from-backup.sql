-- instance: SQL01 (the first node, which pushes its changes to SQL02)
-- ci: skip (Windows only: run 02-publish.sql on SQL02 first)
-- Clip 12.1: the subscriptions of SQL02 to the two publications of SQL01, initialized from the
-- backup of 03-backup.sql: the Distribution Agent delivers what SQL01 committed after it, read
-- by the Distributor of SQL01 in the backup header. One push Distribution Agent per
-- publication, continuous, under the SQL Server Agent service account (PACHADATA\SQL01$ on
-- the network).
--   sqlcmd -S SQL01 -E -C -I -i 05-subscribe-from-backup.sql -v PEER=SQL02
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @p sysname;
DECLARE pubs CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM dbo.syspublications ORDER BY name;
OPEN pubs; FETCH pubs INTO @p;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_addsubscription @publication = @p, @subscriber = N'$(PEER)',
         @destination_db = N'm12_catalog', @subscription_type = N'push',
         @sync_type = N'initialize with backup', @backupdevicetype = N'disk',
         @backupdevicename = N'C:\m12_backup\m12_catalog.bak';
    EXEC sys.sp_addpushsubscription_agent @publication = @p, @subscriber = N'$(PEER)',
         @subscriber_db = N'm12_catalog', @subscriber_security_mode = 1;
    FETCH pubs INTO @p;
END;
CLOSE pubs; DEALLOCATE pubs;
GO
SELECT p.name AS publication, s.srvname AS subscriber, s.dest_db, s.status, s.nosync_type,
       s.loopback_detection
FROM dbo.syssubscriptions AS s
JOIN dbo.sysarticles AS a ON a.artid = s.artid JOIN dbo.syspublications AS p ON p.pubid = a.pubid
WHERE s.srvid >= 0 ORDER BY p.name;
