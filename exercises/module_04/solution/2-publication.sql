-- instance: rpllab1
-- Exercise of module 4, solution, on the publisher: the Log Reader Agent of PachadataTraining,
-- the transactional publication ex_pubCatalog with the rule of the course (@status active,
-- @sync_method concurrent, @allow_pull), its Snapshot Agent run on demand, the three tables of
-- the catalog, and a push subscription to ex_catalog on rpllab3 whose Distribution Agent runs
-- continuously. The agents connect with the SQL Server login of the lab.
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'true';
EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addpublication @publication = N'ex_pubCatalog', @repl_freq = N'continuous',
     @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
     @independent_agent = N'true', @immediate_sync = N'false';
EXEC sys.sp_addpublication_snapshot @publication = N'ex_pubCatalog', @frequency_type = 1,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addarticle @publication = N'ex_pubCatalog', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
EXEC sys.sp_addarticle @publication = N'ex_pubCatalog', @article = N'Course', @source_owner = N'Course', @source_object = N'Course';
EXEC sys.sp_addarticle @publication = N'ex_pubCatalog', @article = N'Session', @source_owner = N'Course', @source_object = N'Session';
EXEC sys.sp_addsubscription @publication = N'ex_pubCatalog', @subscriber = N'rpllab3',
     @destination_db = N'ex_catalog', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
EXEC sys.sp_addpushsubscription_agent @publication = N'ex_pubCatalog', @subscriber = N'rpllab3',
     @subscriber_db = N'ex_catalog', @subscriber_security_mode = 0,
     @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
