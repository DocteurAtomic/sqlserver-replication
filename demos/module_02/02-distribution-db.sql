-- instance: rpllab2
-- Module 2, clip 2.2. The distributor of the course on rpllab2, step by step, with the same
-- parameters as setup/repl-distributor.sql (step dist), and what each step leaves: the linked
-- server repl_distributor and the login distributor_admin, the distribution database (simple
-- recovery model, whatever model says), its retention, the Agent jobs, the agent profiles,
-- then the publisher rpllab1 and its snapshot folder. A folder that does not exist is refused
-- with Msg 21037: the script shows it in a TRY block, then registers the real folder.
SET NOCOUNT ON;
PRINT N'== sp_adddistributor, on the distributor itself';
EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab';
SELECT name, data_source, is_distributor FROM sys.servers WHERE name = N'repl_distributor';
SELECT name, type_desc, is_disabled FROM sys.server_principals WHERE name = N'distributor_admin';
EXEC sys.sp_get_distributor;
GO
PRINT N'== sp_adddistributiondb, defaults kept';
DECLARE @t datetime2 = SYSDATETIME();
EXEC sys.sp_adddistributiondb @database = N'distribution', @security_mode = 1;
PRINT CONCAT(N'distribution database created in ', DATEDIFF(ms, @t, SYSDATETIME()), N' ms');
GO
SELECT name, recovery_model_desc, is_distributor FROM sys.databases WHERE name IN (N'distribution', N'model') ORDER BY name;
EXEC sys.sp_helpdistributiondb @database = N'distribution';
SELECT j.name AS job, c.name AS category, j.enabled
FROM msdb.dbo.sysjobs AS j JOIN msdb.dbo.syscategories AS c ON c.category_id = j.category_id
WHERE c.name LIKE N'REPL-%' ORDER BY c.name, j.name;
SELECT CASE agent_type WHEN 1 THEN N'snapshot' WHEN 2 THEN N'log reader' WHEN 3 THEN N'distribution'
                       WHEN 4 THEN N'merge' WHEN 9 THEN N'queue reader' END AS agent, COUNT(*) AS profiles
FROM msdb.dbo.MSagent_profiles GROUP BY agent_type ORDER BY agent_type;
GO
PRINT N'== sp_adddistpublisher, a snapshot folder that does not exist';
BEGIN TRY
    EXEC sys.sp_adddistpublisher @publisher = N'rpllab1', @distribution_db = N'distribution',
         @security_mode = 0, @login = N'sa', @password = N'Repl-2026!lab',
         @working_directory = N'/var/opt/mssql/share/snapshots';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
    IF ERROR_NUMBER() <> 21037 THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
SELECT COUNT(*) AS publishers_registered FROM msdb.dbo.MSdistpublishers;
GO
PRINT N'== sp_adddistpublisher, the folder on the shared volume';
EXEC sys.sp_adddistpublisher @publisher = N'rpllab1', @distribution_db = N'distribution',
     @security_mode = 0, @login = N'sa', @password = N'Repl-2026!lab',
     @working_directory = N'/var/opt/mssql/share/repldata';
GO
SELECT name, distribution_db, working_directory, security_mode, login FROM msdb.dbo.MSdistpublishers;
EXEC sys.sp_helpdistributor @publisher = N'rpllab1';
