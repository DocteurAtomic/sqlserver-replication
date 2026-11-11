-- instance: rpllab1
-- Exercise of module 10, solution, on the publisher: one SQL Server login per agent, each with
-- a user in PachadataTraining and the role db_owner, no server role (Learn, "Replication Agent
-- Security Model"). The Log Reader Agent and the Snapshot Agent are given their logins, with
-- the password each time: a sp_changelogreader_agent without @publisher_password empties it
-- (clip 10.1). ex_reporting leaves the PAL of ex_pubCatalog. The jobs are restarted by
-- 3-restart.sh: an agent reads its connection when it starts.
SET NOCOUNT ON;
CREATE LOGIN ex_logreader WITH PASSWORD = N'LogReader-2026!ex', CHECK_POLICY = OFF;
CREATE LOGIN ex_snapshot WITH PASSWORD = N'Snapshot-2026!ex', CHECK_POLICY = OFF;
USE PachadataTraining;
CREATE USER ex_logreader FOR LOGIN ex_logreader;
CREATE USER ex_snapshot FOR LOGIN ex_snapshot;
ALTER ROLE db_owner ADD MEMBER ex_logreader;
ALTER ROLE db_owner ADD MEMBER ex_snapshot;
EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0,
     @publisher_login = N'ex_logreader', @publisher_password = N'LogReader-2026!ex';
EXEC sys.sp_changepublication_snapshot @publication = N'ex_pubCatalog', @publisher_security_mode = 0,
     @publisher_login = N'ex_snapshot', @publisher_password = N'Snapshot-2026!ex';
EXEC sys.sp_revoke_publication_access @publication = N'ex_pubCatalog', @login = N'ex_reporting';
