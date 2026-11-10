-- instance: SQL01, then SQL02 (each node of the topology is its own distributor)
-- ci: skip (Windows only: peer-to-peer replication is not supported on Linux)
-- Module 12, starting state of one node: a local distributor, m12_distribution, and the login
-- of the other node's SQL Server Agent, under which its push Distribution Agent connects here.
--   sqlcmd -S SQL01 -E -C -I -i 00-setup-node.sql -v PEER_LOGIN="PACHADATA\SQL02$"
--   sqlcmd -S SQL02 -E -C -I -i 00-setup-node.sql -v PEER_LOGIN="PACHADATA\SQL01$"
SET NOCOUNT ON;
USE master;
IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1)
BEGIN
    DECLARE @me sysname = @@SERVERNAME;
    EXEC sys.sp_adddistributor @distributor = @me, @password = N'M12-Dist-2026!lab';
    EXEC sys.sp_adddistributiondb @database = N'm12_distribution', @security_mode = 1;
    EXEC sys.sp_adddistpublisher @publisher = @me, @distribution_db = N'm12_distribution',
         @security_mode = 1;
END;
GO
IF SUSER_ID(N'$(PEER_LOGIN)') IS NULL CREATE LOGIN [$(PEER_LOGIN)] FROM WINDOWS;
GO
SELECT @@SERVERNAME AS node, SUSER_ID(N'$(PEER_LOGIN)') AS peer_login_id;
EXEC sys.sp_get_distributor;
