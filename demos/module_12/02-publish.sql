-- instance: SQL01, then SQL02 after 04-restore.sql (the same publications on every node)
-- ci: skip (Windows only: peer-to-peer replication is not supported on Linux)
-- Clip 12.1: the two peer-to-peer publications of m12_catalog, identical on every node except
-- for the originator ID: m12_pubCourse (Course, default conflict policy, originatorid) and
-- m12_pubSession (Session, last writer wins, clip 12.2). A table belongs to one peer-to-peer
-- publication only, says Learn (sp_addarticle does not check it: measured, it accepted Course in
-- m12_pubSession). The Log Reader Agent runs under the SQL Server Agent service account.
-- Peer-to-peer requires @sync_method native: concurrent, the rule of the course for a
-- transactional publication, is changed to native with a warning (measured).
--   sqlcmd -S SQL01 -E -C -I -i 02-publish.sql -v ORIGINATOR_ID=1
--   sqlcmd -S SQL02 -E -C -I -i 02-publish.sql -v ORIGINATOR_ID=2
SET NOCOUNT ON;
USE m12_catalog;
EXEC sys.sp_replicationdboption @dbname = N'm12_catalog', @optname = N'publish', @value = N'true';
EXEC sys.sp_addlogreader_agent @publisher_security_mode = 1;
EXEC sys.sp_addpublication @publication = N'm12_pubCourse',
     @description = N'Catalog of courses, written in Paris and in Lyon',
     @status = N'active', @sync_method = N'native', @repl_freq = N'continuous',
     @allow_push = N'true', @allow_pull = N'true', @independent_agent = N'true',
     @allow_initialize_from_backup = N'true', @enabled_for_p2p = N'true',
     @p2p_conflictdetection = N'true', @p2p_originator_id = $(ORIGINATOR_ID);
EXEC sys.sp_addarticle @publication = N'm12_pubCourse', @article = N'Course',
     @source_owner = N'Catalog', @source_object = N'Course';
EXEC sys.sp_addpublication @publication = N'm12_pubSession',
     @description = N'Sessions of both sites, last writer wins',
     @status = N'active', @sync_method = N'native', @repl_freq = N'continuous',
     @allow_push = N'true', @allow_pull = N'true', @independent_agent = N'true',
     @allow_initialize_from_backup = N'true', @enabled_for_p2p = N'true',
     @p2p_conflictdetection = N'true', @p2p_originator_id = $(ORIGINATOR_ID),
     @p2p_continue_onconflict = N'true', @p2p_conflictdetection_policy = N'lastwriter';
EXEC sys.sp_addarticle @publication = N'm12_pubSession', @article = N'Session',
     @source_owner = N'Catalog', @source_object = N'Session';
GO
SELECT p.name, p.options, p.allow_initialize_from_backup, p.immediate_sync, p.sync_method,
       a.name AS article, a.status AS article_status, a.ins_cmd, a.upd_cmd, a.del_cmd
FROM dbo.syspublications AS p JOIN dbo.sysarticles AS a ON a.pubid = p.pubid ORDER BY p.name;
