-- instance: SQL02 (the subscriber: both centres change the same column)
-- ci: skip (Windows only: needs the subscriptions of 03-subscribe.sql)
-- Clip 11.3, two client subscriptions: Lille and Geneva each give session 1004 another room.
--   sqlcmd -S SQL02 -E -C -I -i 10-conflict-two-centres.sql
SET NOCOUNT ON;
UPDATE m11_lille.Training.Session SET Room = 'Lille hall' WHERE SessionId = 1004;
UPDATE m11_geneve.Training.Session SET Room = 'Geneva hall' WHERE SessionId = 1004;
