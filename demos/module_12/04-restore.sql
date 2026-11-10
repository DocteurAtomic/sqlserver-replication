-- instance: SQL02 (the second node, Lyon)
-- ci: skip (Windows only: peer-to-peer replication is not supported on Linux)
-- Clip 12.1: the second node restores the backup of the first, under the same database name,
-- without KEEP_REPLICATION: the publications of SQL01 must not come back here. Then the user
-- of SQL01's SQL Server Agent, under which the push Distribution Agent of SQL01 connects.
--   sqlcmd -S SQL02 -E -C -I -i 04-restore.sql -v PEER_LOGIN="PACHADATA\SQL01$"
SET NOCOUNT ON;
USE master;
RESTORE DATABASE m12_catalog FROM DISK = N'\\SQL01\m12_backup\m12_catalog.bak' WITH RECOVERY;
GO
USE m12_catalog;
IF USER_ID(N'$(PEER_LOGIN)') IS NULL CREATE USER [$(PEER_LOGIN)] FOR LOGIN [$(PEER_LOGIN)];
ALTER ROLE db_owner ADD MEMBER [$(PEER_LOGIN)];
GO
SELECT name, is_published, recovery_model_desc FROM sys.databases WHERE name = N'm12_catalog';
SELECT 'Course' AS tbl, COUNT(*) AS rows_ FROM Catalog.Course
UNION ALL SELECT 'Session', COUNT(*) FROM Catalog.Session;
SELECT COUNT(*) AS publications_restored FROM sys.tables WHERE name = N'syspublications';
