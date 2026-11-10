-- instance: SQL02 (the subscriber: Lille creates a session offline)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, insert conflict: Lille creates session 2001.
--   sqlcmd -S SQL02 -E -C -I -i 12-conflict-insert-centre.sql
SET NOCOUNT ON;
USE m11_lille;
INSERT Training.Session (SessionId, CentreCode, CourseTitle, StartDate, Room, Seats)
VALUES (2001, 'LIL', 'Merge replication', '2027-01-11', 'Room 2', 10);
