-- instance: rpllab2
-- Exercise of module 13, solution, on the distributor: the publisher registration, the
-- distribution database, the distributor, then the subscriber still registered as a remote server.
SET NOCOUNT ON;
EXEC sys.sp_dropdistpublisher @publisher = N'rpllab1';
EXEC sys.sp_dropdistributiondb @database = N'distribution';
EXEC sys.sp_dropdistributor;
EXEC sys.sp_dropserver @server = N'RPLLAB3', @droplogins = N'droplogins';
