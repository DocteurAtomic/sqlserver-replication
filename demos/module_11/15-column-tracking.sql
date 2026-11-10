-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3: column-level tracking on Session. The change invalidates the snapshot and reinitializes both subscriptions:
-- run 02-snapshot.sql then 04-first-sync.sql again afterwards.
--   sqlcmd -S SQL01 -E -C -I -i 15-column-tracking.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_changemergearticle @publication = N'm11_pubCentres', @article = N'Session',
     @property = N'column_tracking', @value = N'true',
     @force_invalidate_snapshot = 1, @force_reinit_subscription = 1;
SELECT name, column_tracking FROM dbo.sysmergearticles WHERE name = N'Session';
