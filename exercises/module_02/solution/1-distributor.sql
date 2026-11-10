-- instance: rpllab2
-- Exercise of module 2, solution, on the distributor: rpllab2 installed as its own distributor,
-- the distribution database ex_distribution, transactions kept 48 hours at most and history
-- 96 hours (both in hours), then rpllab1 registered as its publisher, the agents connecting
-- to it with a SQL Server login, the snapshot folder on the shared volume.
SET NOCOUNT ON;
EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab';
EXEC sys.sp_adddistributiondb @database = N'ex_distribution', @security_mode = 1,
     @max_distretention = 48, @history_retention = 96;
EXEC sys.sp_adddistpublisher @publisher = N'rpllab1', @distribution_db = N'ex_distribution',
     @security_mode = 0, @login = N'sa', @password = N'Repl-2026!lab',
     @working_directory = N'/var/opt/mssql/share/repldata';
