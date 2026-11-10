-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only)
-- Clip 11.4: a parameterized filter changes what each subscription receives, so the course
-- replaces the unfiltered publication: its two subscriptions, then the publication itself.
--   sqlcmd -S SQL01 -E -C -I -i 20-drop-pubCentres.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_dropmergesubscription @publication = N'm11_pubCentres', @subscriber = N'all',
     @subscriber_db = N'all', @subscription_type = N'all';
EXEC sys.sp_dropmergepublication @publication = N'm11_pubCentres';
SELECT COUNT(*) AS merge_publications FROM dbo.sysmergepublications;
SELECT CASE parent_class WHEN 1 THEN 'table triggers' ELSE 'database DDL triggers' END AS kind,
       COUNT(*) AS merge_triggers_left
FROM sys.triggers WHERE name LIKE N'MSmerge[_]%' GROUP BY parent_class;
