-- Run by repl-distributor.sh. The distributor of the course on rpllab2, with rpllab1
-- registered as its publisher: the state module 2 ends with. Variables: STEP (dist or pub).
-- The password of distributor_admin and the agents' SQL logins are those of the lab.
SET NOCOUNT ON;
IF N'$(STEP)' = N'dist'
BEGIN
    EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab';
    EXEC sys.sp_adddistributiondb @database = N'distribution', @security_mode = 1;
    EXEC sys.sp_adddistpublisher @publisher = N'rpllab1', @distribution_db = N'distribution',
         @security_mode = 0, @login = N'sa', @password = N'Repl-2026!lab',
         @working_directory = N'/var/opt/mssql/share/repldata';
END;
IF N'$(STEP)' = N'pub'
    -- SQL Server 2025 refuses a remote distributor whose certificate it does not trust; the
    -- containers have self-signed certificates. Module 2 shows the failure and this option.
    EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab',
         @trust_distributor_certificate = N'yes';
