-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, column-level tracking: Lille raises the seats of session 1005, and its session 2001 is gone with the reinitialization.
--   sqlcmd -S SQL02 -E -C -I -i 16-column-centre.sql
SET NOCOUNT ON;
USE m11_lille;
SELECT SessionId, CourseTitle FROM Training.Session WHERE SessionId = 2001;
UPDATE Training.Session SET Seats = 16 WHERE SessionId = 1005;
