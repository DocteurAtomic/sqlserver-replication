-- instance: SQL01 (Paris)
-- ci: skip (Windows only)
-- Clip 12.1: what a peer-to-peer publication refuses or changes. A row filter (Msg 20646), a
-- subscription initialized by a snapshot (Msg 21679), and the foreign key of Session, which the
-- publication turned into NOT FOR REPLICATION: the Distribution Agent of m12_pubSession may
-- deliver a session before the Distribution Agent of m12_pubCourse delivers its course.
--   sqlcmd -S SQL01 -E -C -I -i 09b-requirements.sql
SET NOCOUNT ON;
USE m12_catalog;
BEGIN TRY
    EXEC sys.sp_articlefilter @publication = N'm12_pubSession', @article = N'Session',
         @filter_name = N'm12_flt_Session', @filter_clause = N'Site = ''PAR''';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
BEGIN TRY
    EXEC sys.sp_addsubscription @publication = N'm12_pubCourse', @subscriber = N'SQL02',
         @destination_db = N'm12_copy', @subscription_type = N'push', @sync_type = N'automatic';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
SELECT name, is_not_for_replication, is_not_trusted FROM sys.foreign_keys;
