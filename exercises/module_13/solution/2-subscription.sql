-- instance: rpllab3
-- Exercise of module 13, solution, on the subscriber: the metadata of the push subscription, that
-- sp_dropsubscription on the publisher leaves in ex_catalog. The data stays.
SET NOCOUNT ON;
USE ex_catalog;
EXEC sys.sp_subscription_cleanup @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
     @publication = N'ex_pubCatalog';
