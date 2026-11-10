-- instance: rpllab1
-- Exercise of module 2, solution, on the publisher: rpllab2 registered as the distributor of
-- rpllab1, with the same distributor_admin password as on rpllab2. The certificate of rpllab2
-- is self-signed: SQL Server 2025 refuses it unless it is trusted, which is the least secure
-- option (module 10 shows the other one).
SET NOCOUNT ON;
EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab',
     @trust_distributor_certificate = N'yes';
