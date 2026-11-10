-- instance: SQL02 (the subscriber: Lille changes a session offline)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, row-level tracking: Lille raises the seats of session 1002.
--   sqlcmd -S SQL02 -E -C -I -i 08-conflict-row-centre.sql
SET NOCOUNT ON;
USE m11_lille;
UPDATE Training.Session SET Seats = 14 WHERE SessionId = 1002;
SELECT SessionId, Room, Seats FROM Training.Session WHERE SessionId = 1002;
