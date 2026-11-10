-- instance: SQL02 (the subscriber of the two regional centres)
-- ci: skip (Windows only: merge replication is not supported on Linux)
-- Module 11, starting state on the subscriber: two empty databases, one per centre, and the
-- login of the publisher's SQL Server Agent, under which the push merge agents connect.
--   sqlcmd -S SQL02 -E -C -I -i 00-setup-subscriber.sql -v AGENT_LOGIN="PACHADATA\SQL01$"
SET NOCOUNT ON;
USE master;
IF DB_ID(N'm11_lille') IS NOT NULL OR DB_ID(N'm11_geneve') IS NOT NULL
BEGIN
    RAISERROR(N'm11_lille or m11_geneve already exists: run 99-cleanup-subscriber.sql first.', 16, 1);
    RETURN;
END;
CREATE DATABASE m11_lille;
ALTER DATABASE m11_lille SET RECOVERY SIMPLE;
CREATE DATABASE m11_geneve;
ALTER DATABASE m11_geneve SET RECOVERY SIMPLE;
GO
IF SUSER_ID(N'$(AGENT_LOGIN)') IS NULL CREATE LOGIN [$(AGENT_LOGIN)] FROM WINDOWS;
GO
USE m11_lille;
CREATE USER [$(AGENT_LOGIN)] FOR LOGIN [$(AGENT_LOGIN)];
ALTER ROLE db_owner ADD MEMBER [$(AGENT_LOGIN)];
GO
USE m11_geneve;
CREATE USER [$(AGENT_LOGIN)] FOR LOGIN [$(AGENT_LOGIN)];
ALTER ROLE db_owner ADD MEMBER [$(AGENT_LOGIN)];
GO
SELECT name, create_date FROM sys.databases WHERE name LIKE N'm11[_]%' ORDER BY name;
