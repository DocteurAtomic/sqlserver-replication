-- instance: SQL01 (the first node, Paris)
-- ci: skip (Windows only: peer-to-peer replication is not supported on Linux)
-- Module 12: the database of the catalog, m12_catalog, created on the first node only. The
-- second node receives it by backup and restore (02 to 04). Two tables: Course, written by
-- Paris and Lyon, and Session, each session belonging to a site. The users of both nodes'
-- Agents are added later, by 04-restore.sql on SQL02 and below for SQL02 on SQL01.
--   sqlcmd -S SQL01 -E -C -I -i 01-create-catalog.sql -v PEER_LOGIN="PACHADATA\SQL02$"
SET NOCOUNT ON;
USE master;
IF DB_ID(N'm12_catalog') IS NOT NULL
BEGIN
    RAISERROR(N'm12_catalog already exists: run 99-cleanup-node.sql first.', 16, 1);
    RETURN;
END;
CREATE DATABASE m12_catalog;
ALTER DATABASE m12_catalog SET RECOVERY FULL;
GO
USE m12_catalog;
GO
CREATE SCHEMA Catalog;
GO
CREATE TABLE Catalog.Course (
    CourseId int NOT NULL CONSTRAINT PK_Course PRIMARY KEY,
    Title varchar(100) NOT NULL,
    DurationDays tinyint NOT NULL,
    Price decimal(8, 2) NOT NULL);
CREATE TABLE Catalog.Session (
    SessionId int NOT NULL CONSTRAINT PK_Session PRIMARY KEY,
    CourseId int NOT NULL CONSTRAINT FK_Session_Course REFERENCES Catalog.Course,
    Site char(3) NOT NULL,
    StartDate date NOT NULL,
    Seats tinyint NOT NULL);
GO
INSERT Catalog.Course (CourseId, Title, DurationDays, Price) VALUES
 (1, 'SQL Server administration', 5, 2950.00), (2, 'Query tuning', 3, 2100.00),
 (3, 'Availability groups', 3, 2250.00), (4, 'Replication', 2, 1600.00),
 (5, 'T-SQL for developers', 4, 2400.00), (6, 'PostgreSQL basics', 3, 1950.00),
 (7, 'Power BI reporting', 2, 1500.00), (8, 'PowerShell for DBAs', 2, 1450.00),
 (9, 'Security and auditing', 2, 1650.00), (10, 'Migrating to SQL Server 2025', 1, 900.00);
WITH n AS (SELECT TOP (40) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects)
INSERT Catalog.Session (SessionId, CourseId, Site, StartDate, Seats)
SELECT 100 + i, 1 + (i - 1) % 10, CASE WHEN i % 2 = 0 THEN 'PAR' ELSE 'LYO' END,
       DATEADD(DAY, 7 * i, '20261116'), 12
FROM n;
GO
CREATE USER [$(PEER_LOGIN)] FOR LOGIN [$(PEER_LOGIN)];
ALTER ROLE db_owner ADD MEMBER [$(PEER_LOGIN)];
GO
SELECT 'Course' AS tbl, COUNT(*) AS rows_ FROM Catalog.Course
UNION ALL SELECT 'Session', COUNT(*) FROM Catalog.Session;
