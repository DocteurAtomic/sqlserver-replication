-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: merge replication is not supported on Linux)
-- Clip 11.1: the merge publication m11_pubCentres of the three tables, row-level tracking and
-- the priority-based resolver by default. Without @publication_compatibility_level, the
-- publication is created at the 80RTM level (measured: backward_comp_level 40). Without
-- @destination_owner, the tables are created in dbo at the subscriber, whatever their schema
-- at the publisher (measured at both levels). Attendance gets automatic identity ranges
-- (clip 11.5).
--   sqlcmd -S SQL01 -E -C -I -i 01-publish.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_replicationdboption @dbname = N'm11_pacha', @optname = N'merge publish', @value = N'true';
EXEC sys.sp_addmergepublication @publication = N'm11_pubCentres',
     @description = N'Sessions and attendance of the regional centres',
     @retention = 14, @allow_push = N'true', @allow_pull = N'true',
     @publication_compatibility_level = N'100RTM';
EXEC sys.sp_addpublication_snapshot @publication = N'm11_pubCentres', @frequency_type = 1;
EXEC sys.sp_addmergearticle @publication = N'm11_pubCentres', @article = N'Centre',
     @source_owner = N'Training', @source_object = N'Centre',
     @destination_owner = N'Training';
EXEC sys.sp_addmergearticle @publication = N'm11_pubCentres', @article = N'Session',
     @source_owner = N'Training', @source_object = N'Session',
     @destination_owner = N'Training';
EXEC sys.sp_addmergearticle @publication = N'm11_pubCentres', @article = N'Attendance',
     @source_owner = N'Training', @source_object = N'Attendance',
     @destination_owner = N'Training',
     @identityrangemanagementoption = N'auto', @pub_identity_range = 1000,
     @identity_range = 100, @threshold = 80;
GO
-- what the articles changed in the published tables
SELECT OBJECT_SCHEMA_NAME(c.object_id) + '.' + OBJECT_NAME(c.object_id) AS table_name,
       c.name AS column_name, TYPE_NAME(c.user_type_id) AS type_name, c.is_rowguidcol,
       dc.definition AS default_value
FROM sys.columns AS c
LEFT JOIN sys.default_constraints AS dc ON dc.object_id = c.default_object_id
WHERE c.object_id IN (OBJECT_ID('Training.Centre'), OBJECT_ID('Training.Session'), OBJECT_ID('Training.Attendance'))
  AND c.is_rowguidcol = 1;
SELECT OBJECT_NAME(parent_id) AS table_name, name AS trigger_name
FROM sys.triggers WHERE parent_class = 1 ORDER BY table_name, trigger_name;
SELECT COUNT(*) AS merge_system_tables FROM sys.tables WHERE name LIKE N'MSmerge[_]%' OR name LIKE N'sysmerge%';
SELECT name, article_resolver, column_tracking, identity_support, pub_range, range, threshold
FROM dbo.sysmergearticles ORDER BY name;
SELECT name, backward_comp_level FROM dbo.sysmergepublications;
SELECT name, destination_owner FROM dbo.sysmergearticles ORDER BY name;
