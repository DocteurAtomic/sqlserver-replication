-- instance: SQL02 (the second node, which pushes its changes to SQL01)
-- ci: skip (Windows only)
-- Clip 12.1: the subscriptions of SQL01 to the two publications of SQL02. SQL01 already has
-- every row, and nothing was written on SQL02 since the restore: "replication support only"
-- only creates the replication procedures at SQL01.
--   sqlcmd -S SQL02 -E -C -I -i 06-subscribe-support-only.sql -v PEER=SQL01
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @p sysname;
DECLARE pubs CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM dbo.syspublications ORDER BY name;
OPEN pubs; FETCH pubs INTO @p;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_addsubscription @publication = @p, @subscriber = N'$(PEER)',
         @destination_db = N'm12_catalog', @subscription_type = N'push',
         @sync_type = N'replication support only';
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
