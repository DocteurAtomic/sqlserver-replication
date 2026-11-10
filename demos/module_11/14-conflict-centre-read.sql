-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3: what Lille holds for sessions 1002, 1004 and 2001 after the conflicts.
--   sqlcmd -S SQL02 -E -C -I -i 14-conflict-centre-read.sql
SET NOCOUNT ON;
SELECT 'm11_lille' AS db, SessionId, CentreCode, CourseTitle, Room, Seats FROM m11_lille.Training.Session WHERE SessionId IN (1002, 1004, 2001)
UNION ALL
SELECT 'm11_geneve', SessionId, CentreCode, CourseTitle, Room, Seats FROM m11_geneve.Training.Session WHERE SessionId IN (1002, 1004, 2001)
ORDER BY 1, 2;
