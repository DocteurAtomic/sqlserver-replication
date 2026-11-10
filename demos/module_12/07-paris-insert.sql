-- instance: SQL01 (Paris)
-- ci: skip (Windows only)
-- Clip 12.1: Paris adds a course and a session to the catalog.
--   sqlcmd -S SQL01 -E -C -I -i 07-paris-insert.sql
SET NOCOUNT ON;
USE m12_catalog;
INSERT Catalog.Course (CourseId, Title, DurationDays, Price)
VALUES (11, 'Peer-to-peer replication', 1, 950.00);
INSERT Catalog.Session (SessionId, CourseId, Site, StartDate, Seats)
VALUES (141, 11, 'PAR', '20270111', 10);
SELECT @@SERVERNAME AS node, CourseId, Title, Price FROM Catalog.Course WHERE CourseId = 11;
