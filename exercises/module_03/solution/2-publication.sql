-- instance: rpllab1
-- Exercise of module 3, solution, on the publisher: snapshot publication ex_pubRef of
-- Reference.Currency, Reference.PaymentMethod and Reference.Holiday, active, its Snapshot Agent
-- once a night at 01:00, a push subscription to ex_ref on rpllab3 whose Distribution Agent runs
-- once a night at 02:00. @frequency_subday = 1 is what makes "once": its default is every
-- 5 minutes. The agents connect with the SQL Server login of the lab.
SET NOCOUNT ON;
USE PachadataTraining;
EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'true';
EXEC sys.sp_addpublication @publication = N'ex_pubRef', @repl_freq = N'snapshot', @status = N'active';
EXEC sys.sp_addpublication_snapshot @publication = N'ex_pubRef',
     @frequency_type = 4, @frequency_interval = 1, @frequency_subday = 1, @active_start_time_of_day = 010000,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addarticle @publication = N'ex_pubRef', @article = N'Currency', @source_owner = N'Reference', @source_object = N'Currency';
EXEC sys.sp_addarticle @publication = N'ex_pubRef', @article = N'PaymentMethod', @source_owner = N'Reference', @source_object = N'PaymentMethod';
EXEC sys.sp_addarticle @publication = N'ex_pubRef', @article = N'Holiday', @source_owner = N'Reference', @source_object = N'Holiday';
EXEC sys.sp_addsubscription @publication = N'ex_pubRef', @subscriber = N'rpllab3', @destination_db = N'ex_ref',
     @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
EXEC sys.sp_addpushsubscription_agent @publication = N'ex_pubRef', @subscriber = N'rpllab3', @subscriber_db = N'ex_ref',
     @subscriber_security_mode = 0, @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab',
     @frequency_type = 4, @frequency_interval = 1, @frequency_subday = 1, @active_start_time_of_day = 020000;
