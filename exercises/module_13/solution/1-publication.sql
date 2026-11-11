-- instance: rpllab1
-- Exercise of module 13, solution, on the publisher: the subscription, the publication, then
-- publishing on PachadataTraining, in this order (sp_droppublication refuses a publication
-- that has a subscription, Msg 14005).
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_dropsubscription @publication = N'ex_pubCatalog', @article = N'all', @subscriber = N'all';
EXEC sys.sp_droppublication @publication = N'ex_pubCatalog';
EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'false';
