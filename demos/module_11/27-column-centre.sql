-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: needs the subscriptions of 23-subscribe-by-centre.sql)
-- Clip 11.4: column-level tracking set when the article was created. Lille raises the seats of
-- its session 1007.
--   sqlcmd -S SQL02 -E -C -I -i 27-column-centre.sql
SET NOCOUNT ON;
UPDATE m11_lille.Training.Session SET Seats = 16 WHERE SessionId = 1007;
