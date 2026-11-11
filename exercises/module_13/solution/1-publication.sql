-- instance: rpllab1
-- Exercise of module 13, solution, on the publisher: the subscription, the publication, then
-- publishing on PachadataTraining, in this order (sp_droppublication refuses a publication
-- that has a subscription, Msg 14005).
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_dropsubscription @publication = N'ex_pubCatalog', @article = N'all', @subscriber = N'all';
EXEC sys.sp_droppublication @publication = N'ex_pubCatalog';
-- The Log Reader Agent calls sp_replcmds on every poll; when this call lands on one, it fails in
-- Msg 18752 (seen once in CI on 11 November 2026). Retry for 30 seconds.
DECLARE @try int = 0;
WHILE 1 = 1
BEGIN
    BEGIN TRY
        EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'false';
        BREAK;
    END TRY
    BEGIN CATCH
        SET @try += 1;
        IF ERROR_NUMBER() <> 18752 OR @try >= 15 THROW;
        WAITFOR DELAY '00:00:02';
    END CATCH;
END;
