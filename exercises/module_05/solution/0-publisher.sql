-- instance: rpllab1
-- Exercise of module 5, solution, on the publisher: the pull subscription of ex_pull, known to
-- the publisher first. ex_pubCatalog allows pull (exercise 4); without @allow_pull, Msg 20012.
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_addsubscription @publication = N'ex_pubCatalog', @subscriber = N'rpllab3',
     @destination_db = N'ex_pull', @subscription_type = N'pull', @sync_type = N'automatic', @article = N'all';
