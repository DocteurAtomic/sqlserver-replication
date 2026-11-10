-- instance: rpllab1
-- Module 1, clip 1.1: what the registration site needs, against the whole database.
-- Read-only: sizes and row counts of the three catalog tables and of the database, what else
-- lives in the database, and the foreign keys that point outside the three tables.
SET NOCOUNT ON;
USE PachadataTraining;

PRINT 'The three tables the registration site reads';
SELECT s.name + N'.' + t.name AS table_name,
       SUM(CASE WHEN p.index_id IN (0, 1) THEN p.row_count ELSE 0 END) AS row_count,
       CAST(SUM(p.reserved_page_count) * 8 / 1024.0 AS decimal(9, 1)) AS reserved_mb,
       CASE WHEN OBJECTPROPERTY(t.object_id, 'TableHasPrimaryKey') = 1 THEN 'yes' ELSE 'no' END AS has_primary_key
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.dm_db_partition_stats AS p ON p.object_id = t.object_id
WHERE s.name = N'Course' AND t.name IN (N'Category', N'Course', N'Session')
GROUP BY s.name, t.name, t.object_id
ORDER BY table_name;

PRINT 'The whole database';
SELECT COUNT(DISTINCT t.object_id) AS user_tables,
       CAST(SUM(p.reserved_page_count) * 8 / 1024.0 AS decimal(9, 1)) AS reserved_mb
FROM sys.tables AS t
JOIN sys.dm_db_partition_stats AS p ON p.object_id = t.object_id
WHERE t.is_ms_shipped = 0;

PRINT 'What else lives in the database: a publication picks its articles among these objects';
SELECT o.type_desc AS object_type, COUNT(*) AS objects
FROM sys.objects AS o
WHERE o.is_ms_shipped = 0
  AND o.type IN ('U', 'V', 'P', 'FN', 'IF', 'TF', 'TR', 'SN')
GROUP BY o.type_desc
ORDER BY objects DESC;

PRINT 'Foreign keys of the three tables, and whether the table they point to is in the copy';
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + N'.' + OBJECT_NAME(fk.parent_object_id) AS from_table,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + N'.' + OBJECT_NAME(fk.referenced_object_id) AS to_table,
       CASE WHEN fk.referenced_object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'),
                                             OBJECT_ID(N'Course.Session'))
            THEN 'yes' ELSE 'no' END AS target_in_copy
FROM sys.foreign_keys AS fk
WHERE fk.parent_object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'), OBJECT_ID(N'Course.Session'))
ORDER BY from_table, to_table;
