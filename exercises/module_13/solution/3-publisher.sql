-- instance: rpllab1
-- Exercise of module 13, solution: the publisher drops its remote distributor first (the
-- distributor refuses to drop a publisher that still uses it, Msg 14098), then the subscriber,
-- still registered as a remote server.
SET NOCOUNT ON;
EXEC sys.sp_dropdistributor;
EXEC sys.sp_dropserver @server = N'RPLLAB3', @droplogins = N'droplogins';
