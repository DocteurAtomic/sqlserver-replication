-- instance: rpllab1
-- ci: skip (run by 00-setup.sh)
-- Module 13, setup on the publisher: m13_Catalog, a copy of the catalog of PachadataTraining
-- (Course.Category, Course.Course, Course.Session with their primary keys), in the full
-- recovery model with a first full backup, published by m13_pubCatalog with the rule of the
-- course and pushed to m13_Catalog on rpllab3. The restore of clip 13.1 is played on this copy,
-- never on PachadataTraining.
SET NOCOUNT ON;
CREATE DATABASE m13_Catalog;
ALTER DATABASE m13_Catalog SET RECOVERY FULL;
GO
USE m13_Catalog;
EXEC (N'CREATE SCHEMA Course');
SELECT * INTO Course.Category FROM PachadataTraining.Course.Category;
SELECT * INTO Course.Course FROM PachadataTraining.Course.Course;
SELECT * INTO Course.Session FROM PachadataTraining.Course.Session;
ALTER TABLE Course.Category ADD CONSTRAINT pk_Category PRIMARY KEY (CategoryCode);
ALTER TABLE Course.Course ADD CONSTRAINT pk_Course PRIMARY KEY (CourseId);
ALTER TABLE Course.Session ADD CONSTRAINT pk_Session PRIMARY KEY (SessionId);
BACKUP DATABASE m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-full.bak' WITH INIT, COMPRESSION;
GO
USE m13_Catalog;
EXEC sys.sp_replicationdboption @dbname = N'm13_Catalog', @optname = N'publish', @value = N'true';
EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addpublication @publication = N'm13_pubCatalog', @repl_freq = N'continuous',
     @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
     @independent_agent = N'true', @immediate_sync = N'false';
EXEC sys.sp_addpublication_snapshot @publication = N'm13_pubCatalog', @frequency_type = 1,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addarticle @publication = N'm13_pubCatalog', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
EXEC sys.sp_addarticle @publication = N'm13_pubCatalog', @article = N'Course', @source_owner = N'Course', @source_object = N'Course';
EXEC sys.sp_addarticle @publication = N'm13_pubCatalog', @article = N'Session', @source_owner = N'Course', @source_object = N'Session';
EXEC sys.sp_addsubscription @publication = N'm13_pubCatalog', @subscriber = N'rpllab3',
     @destination_db = N'm13_Catalog', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
EXEC sys.sp_addpushsubscription_agent @publication = N'm13_pubCatalog', @subscriber = N'rpllab3',
     @subscriber_db = N'm13_Catalog', @subscriber_security_mode = 0,
     @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
EXEC sys.sp_startpublication_snapshot @publication = N'm13_pubCatalog';
