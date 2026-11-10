-- instance: rpllab1
-- Module 3, clip 3.1. The snapshot publication of the finance department, pubReference, and
-- the defaults of the procedures that build it, measured on 10 November 2026: a snapshot
-- publication refuses @sync_method = N'concurrent' (Msg 22547); without @status it is
-- inactive and refuses subscriptions (Msg 21000); a daily Snapshot Agent without
-- @frequency_subday runs every 5 minutes. Then the same tables in a transactional
-- publication, m03_pubConcurrent, used by clip 3.2: a table without a primary key is refused
-- there (Msg 14088), and the default schema options differ (0x30071 against 0x30073).
-- Needs 00-setup.sh first.
SET NOCOUNT ON;
USE PachadataTraining;
PRINT N'== sp_replicationdboption';
EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'true';
SELECT name, is_published FROM sys.databases WHERE name = N'PachadataTraining';
GO
PRINT N'== A snapshot publication with @sync_method = N''concurrent''';
BEGIN TRY
    EXEC sys.sp_addpublication @publication = N'm03_probe', @repl_freq = N'snapshot', @sync_method = N'concurrent';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
    IF ERROR_NUMBER() <> 22547 THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
GO
PRINT N'== pubReference, with the defaults of sp_addpublication';
EXEC sys.sp_addpublication @publication = N'pubReference', @repl_freq = N'snapshot',
     @description = N'Reference tables for the finance department, every night';
SELECT name, repl_freq, status, sync_method, immediate_sync, independent_agent,
       allow_push, allow_pull, retention
FROM dbo.syspublications WHERE name = N'pubReference';
GO
PRINT N'== The Snapshot Agent, every day at 01:00';
EXEC sys.sp_addpublication_snapshot @publication = N'pubReference',
     @frequency_type = 4, @frequency_interval = 1, @active_start_time_of_day = 010000,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_helppublication_snapshot @publication = N'pubReference';
GO
PRINT N'== Once a day: @frequency_subday = 1';
-- The password is given again: an agent change without it would leave it empty.
EXEC sys.sp_changepublication_snapshot @publication = N'pubReference',
     @frequency_type = 4, @frequency_interval = 1, @frequency_subday = 1, @active_start_time_of_day = 010000,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_helppublication_snapshot @publication = N'pubReference';
GO
PRINT N'== The articles, one of them without a primary key';
EXEC sys.sp_addarticle @publication = N'pubReference', @article = N'Country', @source_owner = N'Reference', @source_object = N'Country';
EXEC sys.sp_addarticle @publication = N'pubReference', @article = N'City', @source_owner = N'Reference', @source_object = N'City';
EXEC sys.sp_addarticle @publication = N'pubReference', @article = N'VatRate', @source_owner = N'Reference', @source_object = N'VatRate';
EXEC sys.sp_addarticle @publication = N'pubReference', @article = N'CurrencyArchive', @source_owner = N'Reference', @source_object = N'CurrencyArchive';
SELECT a.name AS article, OBJECTPROPERTY(a.objid, 'TableHasPrimaryKey') AS has_pk,
       CONVERT(varchar(18), a.schema_option, 1) AS schema_option, a.pre_creation_cmd
FROM dbo.sysarticles AS a JOIN dbo.syspublications AS p ON p.pubid = a.pubid
WHERE p.name = N'pubReference' ORDER BY a.artid;
GO
PRINT N'== A subscription to the inactive publication';
BEGIN TRY
    EXEC sys.sp_addsubscription @publication = N'pubReference', @subscriber = N'rpllab3',
         @destination_db = N'PachaReporting', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
    IF ERROR_NUMBER() <> 21000 THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
EXEC sys.sp_changepublication @publication = N'pubReference', @property = N'status', @value = N'active';
SELECT name, status FROM dbo.syspublications WHERE name = N'pubReference';
GO
PRINT N'== The same tables in a transactional publication';
EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
-- immediate_sync: the Snapshot Agent writes a snapshot even without a subscription (clip 3.2).
EXEC sys.sp_addpublication @publication = N'm03_pubConcurrent', @repl_freq = N'continuous',
     @status = N'active', @sync_method = N'concurrent', @independent_agent = N'true', @immediate_sync = N'true';
EXEC sys.sp_addpublication_snapshot @publication = N'm03_pubConcurrent', @frequency_type = 1,
     @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
EXEC sys.sp_addarticle @publication = N'm03_pubConcurrent', @article = N'Country', @source_owner = N'Reference', @source_object = N'Country';
EXEC sys.sp_addarticle @publication = N'm03_pubConcurrent', @article = N'City', @source_owner = N'Reference', @source_object = N'City';
EXEC sys.sp_addarticle @publication = N'm03_pubConcurrent', @article = N'VatRate', @source_owner = N'Reference', @source_object = N'VatRate';
BEGIN TRY
    EXEC sys.sp_addarticle @publication = N'm03_pubConcurrent', @article = N'CurrencyArchive', @source_owner = N'Reference', @source_object = N'CurrencyArchive';
END TRY
BEGIN CATCH
    PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
    IF ERROR_NUMBER() <> 14088 THROW;
END CATCH;
IF @@TRANCOUNT > 0 ROLLBACK;
SELECT p.name AS publication, p.repl_freq, p.sync_method, a.name AS article,
       CONVERT(varchar(18), a.schema_option, 1) AS schema_option
FROM dbo.sysarticles AS a JOIN dbo.syspublications AS p ON p.pubid = a.pubid
ORDER BY p.name, a.artid;
