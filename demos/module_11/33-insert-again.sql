-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: run 32-new-range.sql first)
-- Clip 11.5: after the synchronization, the check constraint has moved and Lille inserts again.
--   sqlcmd -S SQL02 -E -C -I -i 33-insert-again.sql
SET NOCOUNT ON;
USE m11_lille;
SELECT name, definition FROM sys.check_constraints WHERE name LIKE N'repl[_]identity[_]range%';
INSERT Training.Attendance (SessionId, TraineeName, AttendanceDate, Present)
VALUES (1001, 'Walk-in 201', '2026-11-18', 1);
SELECT AttendanceId, TraineeName FROM Training.Attendance WHERE TraineeName = 'Walk-in 201';
