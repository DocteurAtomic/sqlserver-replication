-- instance: SQL01 (Paris)
-- ci: skip (Windows only: run it after 08-lyon-read-insert.sql on SQL02)
-- Clip 12.1: the course of Lyon arrives in Paris, and both nodes now hold the same catalog.
-- Then the commands of the Distributor of SQL01: each one carries the node it comes from.
--   sqlcmd -S SQL01 -E -C -I -i 09-paris-read.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @i int = 0;
WHILE (NOT EXISTS (SELECT 1 FROM Catalog.Course WHERE CourseId = 12)
       OR NOT EXISTS (SELECT 1 FROM Catalog.Session WHERE SessionId = 142)) AND @i < 120
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT @@SERVERNAME AS node, c.CourseId, c.Title, s.SessionId, s.Site
FROM Catalog.Course AS c JOIN Catalog.Session AS s ON s.CourseId = c.CourseId
WHERE c.CourseId IN (11, 12) ORDER BY c.CourseId;
SELECT 'Course' AS tbl, COUNT(*) AS rows_ FROM Catalog.Course
UNION ALL SELECT 'Session', COUNT(*) FROM Catalog.Session;
