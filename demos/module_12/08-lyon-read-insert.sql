-- instance: SQL02 (Lyon)
-- ci: skip (Windows only: run it after 07-paris-insert.sql on SQL01)
-- Clip 12.1: Lyon waits for the course of Paris (a bounded loop on the row, one minute at
-- most), then adds its own course and session.
--   sqlcmd -S SQL02 -E -C -I -i 08-lyon-read-insert.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @i int = 0;
WHILE (NOT EXISTS (SELECT 1 FROM Catalog.Course WHERE CourseId = 11)
       OR NOT EXISTS (SELECT 1 FROM Catalog.Session WHERE SessionId = 141)) AND @i < 120
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT @@SERVERNAME AS node, c.CourseId, c.Title, s.SessionId, s.Site
FROM Catalog.Course AS c LEFT JOIN Catalog.Session AS s ON s.CourseId = c.CourseId
WHERE c.CourseId = 11;
INSERT Catalog.Course (CourseId, Title, DurationDays, Price)
VALUES (12, 'Merge replication', 1, 950.00);
INSERT Catalog.Session (SessionId, CourseId, Site, StartDate, Seats)
VALUES (142, 12, 'LYO', '20270118', 10);
