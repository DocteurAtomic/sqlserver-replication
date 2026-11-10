-- instance: SQL01 (the publisher, which is also its own distributor)
-- ci: skip (Windows only: merge replication is not supported on Linux)
-- Module 11, starting state on the publisher: a local distributor, m11_distribution, and the
-- database m11_pacha with three tables of the regional centres. Run 00-setup-folder.ps1
-- first, then:
--   sqlcmd -S SQL01 -E -C -I -i 00-setup-publisher.sql
SET NOCOUNT ON;
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1)
BEGIN
    DECLARE @me sysname = @@SERVERNAME;
    EXEC sys.sp_adddistributor @distributor = @me, @password = N'M11-Dist-2026!lab';
    EXEC sys.sp_adddistributiondb @database = N'm11_distribution', @security_mode = 1;
    -- the snapshot folder of 00-setup-folder.ps1, writable by the SQL Server Agent service
    EXEC sys.sp_adddistpublisher @publisher = @me, @distribution_db = N'm11_distribution',
         @security_mode = 1, @working_directory = N'C:\m11_repldata';
END;
GO
IF DB_ID(N'm11_pacha') IS NOT NULL
BEGIN
    RAISERROR(N'm11_pacha already exists: run 99-cleanup-publisher.sql first.', 16, 1);
    RETURN;
END;
CREATE DATABASE m11_pacha;
ALTER DATABASE m11_pacha SET RECOVERY SIMPLE;
GO
USE m11_pacha;
GO
CREATE SCHEMA Training;
GO
CREATE TABLE Training.Centre (
    CentreCode char(3) NOT NULL CONSTRAINT PK_Centre PRIMARY KEY,
    Name varchar(50) NOT NULL,
    City varchar(50) NOT NULL);
CREATE TABLE Training.Session (
    SessionId int NOT NULL CONSTRAINT PK_Session PRIMARY KEY,
    CentreCode char(3) NOT NULL CONSTRAINT FK_Session_Centre REFERENCES Training.Centre,
    CourseTitle varchar(100) NOT NULL,
    StartDate date NOT NULL,
    Room varchar(30) NULL,
    Seats tinyint NOT NULL);
CREATE TABLE Training.Attendance (
    AttendanceId int IDENTITY(1, 1) NOT NULL CONSTRAINT PK_Attendance PRIMARY KEY,
    SessionId int NOT NULL CONSTRAINT FK_Attendance_Session REFERENCES Training.Session,
    TraineeName varchar(60) NOT NULL,
    AttendanceDate date NOT NULL,
    Present bit NOT NULL,
    Remark varchar(200) NULL);
GO
INSERT Training.Centre (CentreCode, Name, City) VALUES
    ('LIL', 'Centre Pacha Lille', 'Lille'),
    ('GEN', 'Centre Pacha Geneve', 'Geneve'),
    ('DEF', 'Centre Pacha Defense', 'La Defense');
-- ten sessions per centre, numbered 1001 to 1030
WITH n AS (SELECT TOP (30) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i FROM sys.all_objects)
INSERT Training.Session (SessionId, CentreCode, CourseTitle, StartDate, Room, Seats)
SELECT 1000 + i,
       CHOOSE((i - 1) % 3 + 1, 'LIL', 'GEN', 'DEF'),
       CHOOSE((i - 1) % 5 + 1, 'SQL Server administration', 'Query tuning', 'Replication',
              'Availability groups', 'PowerShell for DBAs'),
       DATEADD(DAY, 7 * ((i - 1) / 3), '2026-11-16'),
       CONCAT('Room ', (i - 1) % 4 + 1), 12
FROM n;
-- eight trainees per session, one attendance line each for the first day
WITH t AS (SELECT TOP (8) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS k FROM sys.all_objects)
INSERT Training.Attendance (SessionId, TraineeName, AttendanceDate, Present)
SELECT s.SessionId,
       CONCAT(CHOOSE(t.k, 'Alice', 'Bruno', 'Chloe', 'David', 'Emma', 'Farid', 'Gaelle', 'Hugo'),
              ' ', CHOOSE((s.SessionId + t.k) % 6 + 1, 'Martin', 'Bernard', 'Dubois', 'Petit',
              'Moreau', 'Lefevre')),
       s.StartDate, 1
FROM Training.Session AS s CROSS JOIN t
ORDER BY s.SessionId, t.k;
GO
SELECT 'Centre' AS tbl, COUNT(*) AS rows_ FROM Training.Centre
UNION ALL SELECT 'Session', COUNT(*) FROM Training.Session
UNION ALL SELECT 'Attendance', COUNT(*) FROM Training.Attendance;
EXEC sys.sp_get_distributor;
