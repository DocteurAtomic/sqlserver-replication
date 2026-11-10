-- instance: SQL02 (the subscriber: the Lille centre writes offline)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.2: the Lille centre records an attendance line on its own database, with no
-- connection to the publisher; the merge triggers note the change for the next upload.
--   sqlcmd -S SQL02 -E -C -I -i 05-roundtrip-centre.sql
SET NOCOUNT ON;
USE m11_lille;
INSERT Training.Attendance (SessionId, TraineeName, AttendanceDate, Present, Remark)
VALUES (1001, 'Ines Garnier', '2026-11-17', 1, 'Joined on the second day');
SELECT AttendanceId, SessionId, TraineeName, AttendanceDate, rowguid
FROM Training.Attendance WHERE TraineeName = 'Ines Garnier';
SELECT COUNT(*) AS changes_noted FROM dbo.MSmerge_contents;
