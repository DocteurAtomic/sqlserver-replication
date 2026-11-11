-- instance: rpllab1
-- Exercise of module 6, solution, on the publisher. ex_pubCatalog has @immediate_sync false and
-- concurrent snapshot processing (exercise 4): the new article needs no flag, and its
-- subscription is added with @article = N'all' (the article alone is refused in Msg 14100). The
-- row filter of a subscribed article needs @force_reinit_subscription = 1, which reinitializes
-- the article Session alone; sp_articleview rebuilds its synchronization view. One snapshot,
-- started by 2-deliver.sh, then copies CourseLanguage and Session, and nothing else.
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_addarticle @publication = N'ex_pubCatalog', @article = N'CourseLanguage',
     @source_owner = N'Course', @source_object = N'CourseLanguage';
EXEC sys.sp_addsubscription @publication = N'ex_pubCatalog', @subscriber = N'rpllab3',
     @destination_db = N'ex_catalog', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
EXEC sys.sp_articlefilter @publication = N'ex_pubCatalog', @article = N'Session', @filter_name = N'FLTR_ex_Session',
     @filter_clause = N'StatusCode <> ''CANCELED''', @force_reinit_subscription = 1;
EXEC sys.sp_articleview @publication = N'ex_pubCatalog', @article = N'Session', @view_name = N'SYNC_ex_Session',
     @filter_clause = N'StatusCode <> ''CANCELED''';
