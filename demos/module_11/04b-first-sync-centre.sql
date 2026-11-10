-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: run 04-first-sync.sql first)
-- Clip 11.2: what the first synchronization left in each centre: the rows, the merge triggers
-- and the identity range check constraint.
--   sqlcmd -S SQL02 -E -C -I -i 04b-first-sync-centre.sql
SET NOCOUNT ON;
SELECT 'm11_lille' AS db, (SELECT COUNT(*) FROM m11_lille.Training.Centre) AS centres, (SELECT COUNT(*) FROM m11_lille.Training.Session) AS sessions, (SELECT COUNT(*) FROM m11_lille.Training.Attendance) AS attendance
UNION ALL SELECT 'm11_geneve', (SELECT COUNT(*) FROM m11_geneve.Training.Centre), (SELECT COUNT(*) FROM m11_geneve.Training.Session), (SELECT COUNT(*) FROM m11_geneve.Training.Attendance);
USE m11_lille;
SELECT OBJECT_NAME(parent_id) AS table_name, name AS trigger_name FROM sys.triggers WHERE parent_class = 1 ORDER BY 1, 2;
SELECT name, definition FROM sys.check_constraints WHERE name LIKE N'repl[_]identity%';
SELECT IDENT_CURRENT('Training.Attendance') AS ident_current;
