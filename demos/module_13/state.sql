-- ci: skip (read by demos/module_13/lib.sh, on each instance)
-- What replication leaves on an instance, one line per object: distribution database, published
-- databases, server entries (repl_distributor, publisher, subscriber), replication jobs, the login
-- distributor_admin, the publishers registered at a distributor, and the subscription metadata
-- (dbo.MSreplication_subscriptions) of a subscription database, which sys.databases does not show:
-- its column is_subscribed is not used and always 0. Nothing when the instance is clean.
SET NOCOUNT ON;
DECLARE @r TABLE (what nvarchar(400));
INSERT @r SELECT N'distribution database ' + name FROM sys.databases WHERE is_distributor = 1;
INSERT @r SELECT N'published database ' + name FROM sys.databases WHERE is_published = 1 OR is_merge_published = 1;
INSERT @r SELECT N'subscribed database ' + name FROM sys.databases WHERE is_subscribed = 1;
INSERT @r SELECT N'server ' + name + N' (distributor ' + LTRIM(is_distributor) + N', subscriber ' + LTRIM(is_subscriber) + N')' FROM sys.servers WHERE server_id > 0;
INSERT @r SELECT N'job ' + j.name + N' (' + c.name + N')' FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id WHERE c.name LIKE N'REPL-%';
INSERT @r SELECT N'login distributor_admin' FROM sys.server_principals WHERE name = N'distributor_admin';
IF OBJECT_ID(N'msdb.dbo.MSdistpublishers') IS NOT NULL INSERT @r SELECT N'publisher registered: ' + name FROM msdb.dbo.MSdistpublishers;
DECLARE @q nvarchar(max) = N'';
SELECT @q += N'IF OBJECT_ID(N''' + QUOTENAME(name) + N'.dbo.MSreplication_subscriptions'') IS NOT NULL SELECT N''subscription metadata in ' + name + N': '' + publication FROM ' + QUOTENAME(name) + N'.dbo.MSreplication_subscriptions;'
FROM sys.databases WHERE database_id > 4 AND state_desc = N'ONLINE';
INSERT @r EXEC (@q);
SELECT @@SERVERNAME + N': ' + what FROM @r;
