-- instance: SQL02 (the subscriber of the two centres)
-- ci: skip (Windows only)
-- Module 11, cleanup on the subscriber, after 99-cleanup-publisher.sql: the two databases of
-- the centres and the login of the publisher's SQL Server Agent. Safe to run twice.
--   sqlcmd -S SQL02 -E -C -I -i 99-cleanup-subscriber.sql -v AGENT_LOGIN="PACHADATA\SQL01$"
SET NOCOUNT ON;
USE master;
IF DB_ID(N'm11_lille') IS NOT NULL
BEGIN
    ALTER DATABASE m11_lille SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE m11_lille;
END;
IF DB_ID(N'm11_geneve') IS NOT NULL
BEGIN
    ALTER DATABASE m11_geneve SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE m11_geneve;
END;
IF SUSER_ID(N'$(AGENT_LOGIN)') IS NOT NULL DROP LOGIN [$(AGENT_LOGIN)];
GO
SELECT name FROM sys.databases WHERE name LIKE N'm11[_]%';
SELECT name FROM sys.server_principals WHERE name = N'$(AGENT_LOGIN)';
