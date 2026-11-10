-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only)
-- Clip 11.4: session 1004 and its attendance lines, centre by centre, after the move.
--   sqlcmd -S SQL02 -E -C -I -i 26-move-check.sql
SET NOCOUNT ON;
SELECT 'm11_lille' AS centre_db, COUNT(*) AS session_1004,
       (SELECT COUNT(*) FROM m11_lille.Training.Attendance WHERE SessionId = 1004) AS attendance_1004
FROM m11_lille.Training.Session WHERE SessionId = 1004
UNION ALL
SELECT 'm11_geneve', COUNT(*), (SELECT COUNT(*) FROM m11_geneve.Training.Attendance WHERE SessionId = 1004)
FROM m11_geneve.Training.Session WHERE SessionId = 1004;
