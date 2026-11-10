-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run 02-snapshot.sql first)
-- Clip 11.1: what the snapshot added to the published tables: the rowguid column, three merge
-- triggers per table, the conflict tables and the identity range check constraint.
--   sqlcmd -S SQL01 -E -C -I -i 02b-what-changed.sql
SET NOCOUNT ON; USE m11_pacha;
SELECT OBJECT_SCHEMA_NAME(c.object_id)+'.'+OBJECT_NAME(c.object_id) AS table_name, c.name, TYPE_NAME(c.user_type_id) ty, dc.definition
FROM sys.columns c LEFT JOIN sys.default_constraints dc ON dc.object_id=c.default_object_id WHERE c.is_rowguidcol=1;
SELECT OBJECT_NAME(parent_id) AS table_name, name FROM sys.triggers WHERE parent_class=1 ORDER BY 1,2;
SELECT name, identity_support, pub_range, range, threshold FROM dbo.sysmergearticles;
SELECT name, OBJECT_NAME(parent_object_id) t, definition FROM sys.check_constraints;
SELECT COUNT(*) contents FROM dbo.MSmerge_contents; SELECT COUNT(*) tomb FROM dbo.MSmerge_tombstone; SELECT COUNT(*) gen FROM dbo.MSmerge_genhistory;
SELECT name, publication_compatibility_level=backward_comp_level, use_partition_groups, dynamic_filters FROM dbo.sysmergepublications;
