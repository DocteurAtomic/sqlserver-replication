-- instance: rpllab1
-- Run by repl-catalog.sh. The catalog of PachaData published to the registration site:
-- publication pubCatalog (Course.Category, Course.Course, Course.Session), transactional,
-- pushed to PachaCatalog on rpllab3. The state module 4 ends with.
-- sp_addpublication defaults, measured on 10 November 2026, that the course does not keep:
-- @status inactive (no subscription possible), @allow_pull false, @sync_method native (tables
-- locked for the whole snapshot).
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'true';
EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addpublication @publication = N'pubCatalog', @repl_freq = N'continuous',
     @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
     @independent_agent = N'true', @immediate_sync = N'false';
EXEC sys.sp_addpublication_snapshot @publication = N'pubCatalog', @frequency_type = 1,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Course', @source_owner = N'Course', @source_object = N'Course';
EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Session', @source_owner = N'Course', @source_object = N'Session';
EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3',
     @destination_db = N'PachaCatalog', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
EXEC sys.sp_addpushsubscription_agent @publication = N'pubCatalog', @subscriber = N'rpllab3',
     @subscriber_db = N'PachaCatalog', @subscriber_security_mode = 0,
     @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';
