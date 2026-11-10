-- Run by repl-state.sh on each instance, with the variable N set to the instance name.
-- One row per replication object still present on the instance; nothing when it has none.
SET NOCOUNT ON;
DECLARE @r TABLE (what nvarchar(400));
INSERT @r SELECT N'distribution database ' + name FROM sys.databases WHERE is_distributor = 1;
INSERT @r SELECT N'published database ' + name FROM sys.databases
    WHERE is_published = 1 OR is_merge_published = 1;
INSERT @r SELECT N'subscribed database ' + name FROM sys.databases WHERE is_subscribed = 1;
INSERT @r SELECT N'linked or remote server ' + name FROM sys.servers
    WHERE server_id > 0 AND (is_distributor = 1 OR name = N'repl_distributor' OR is_publisher = 1 OR is_subscriber = 1);
INSERT @r SELECT N'replication job ' + j.name FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE c.name LIKE N'REPL-%';
INSERT @r SELECT N'login distributor_admin' FROM sys.server_principals WHERE name = N'distributor_admin';
IF OBJECT_ID(N'msdb.dbo.MSdistpublishers') IS NOT NULL
    INSERT @r SELECT N'publisher registered at this distributor: ' + name FROM msdb.dbo.MSdistpublishers;
SELECT N'$(N): ' + what FROM @r;
