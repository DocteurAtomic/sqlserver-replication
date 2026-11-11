-- instance: rpllab3
-- Exercise of module 5, solution, on the subscriber: the schema the snapshot will not create,
-- then the pull subscription and its Distribution Agent, which runs here, continuously. Under
-- Linux the agent connects to the distributor with a SQL Server login: with the default,
-- Windows authentication, it fails with Agent message code 20084. Run after 0-publisher.sql
-- (the order of Learn: the publisher knows the subscription first).
SET NOCOUNT ON;
USE ex_pull;
IF SCHEMA_ID(N'Course') IS NULL EXEC (N'CREATE SCHEMA Course');
EXEC sys.sp_addpullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
     @publication = N'ex_pubCatalog', @subscription_type = N'pull';
EXEC sys.sp_addpullsubscription_agent @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
     @publication = N'ex_pubCatalog', @distributor = N'rpllab2',
     @distributor_security_mode = 0, @distributor_login = N'sa', @distributor_password = N'Repl-2026!lab',
     @frequency_type = 64;
