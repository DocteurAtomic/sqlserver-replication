-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only)
-- Clip 11.2: the two centres agree with head office: the new line and the new room.
--   sqlcmd -S SQL02 -E -C -I -i 07-roundtrip-check.sql
SET NOCOUNT ON;
SELECT 'm11_lille' AS centre_db, s.Room, (SELECT COUNT(*) FROM m11_lille.Training.Attendance) AS attendance_rows
FROM m11_lille.Training.Session AS s WHERE s.SessionId = 1001
UNION ALL
SELECT 'm11_geneve', s.Room, (SELECT COUNT(*) FROM m11_geneve.Training.Attendance)
FROM m11_geneve.Training.Session AS s WHERE s.SessionId = 1001;
