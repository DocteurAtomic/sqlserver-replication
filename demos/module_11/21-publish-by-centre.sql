-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run 20-drop-pubCentres.sql first)
-- Clip 11.4: m11_pubByCentre. Centre is download-only and unfiltered; Session is filtered by
-- HOST_NAME(), with column-level tracking set at creation; Attendance follows its session
-- through a join filter, with automatic identity ranges of 100 values (clip 11.5).
--   sqlcmd -S SQL01 -E -C -I -i 21-publish-by-centre.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC sys.sp_addmergepublication @publication = N'm11_pubByCentre',
     @description = N'Each centre receives its own sessions and their attendance',
     @publication_compatibility_level = N'100RTM';
EXEC sys.sp_addpublication_snapshot @publication = N'm11_pubByCentre', @frequency_type = 1;
EXEC sys.sp_addmergearticle @publication = N'm11_pubByCentre', @article = N'Centre',
     @source_owner = N'Training', @source_object = N'Centre', @destination_owner = N'Training',
     @subscriber_upload_options = 2;
EXEC sys.sp_addmergearticle @publication = N'm11_pubByCentre', @article = N'Session',
     @source_owner = N'Training', @source_object = N'Session', @destination_owner = N'Training',
     @column_tracking = N'true', @subset_filterclause = N'CentreCode = HOST_NAME()';
EXEC sys.sp_addmergearticle @publication = N'm11_pubByCentre', @article = N'Attendance',
     @source_owner = N'Training', @source_object = N'Attendance', @destination_owner = N'Training',
     @identityrangemanagementoption = N'auto', @pub_identity_range = 1000,
     @identity_range = 100, @threshold = 80;
EXEC sys.sp_addmergefilter @publication = N'm11_pubByCentre', @article = N'Attendance',
     @filtername = N'Attendance_Session', @join_articlename = N'Session',
     @join_filterclause = N'[Session].[SessionId] = [Attendance].[SessionId]',
     @join_unique_key = 1, @filter_type = 1;
GO
SELECT name, dynamic_filters, use_partition_groups, dynamic_filters_function_list
FROM dbo.sysmergepublications WHERE name = N'm11_pubByCentre';
SELECT a.name, a.column_tracking, a.upload_options, a.subset_filterclause
FROM dbo.sysmergearticles AS a
JOIN dbo.sysmergepublications AS p ON p.pubid = a.pubid
WHERE p.name = N'm11_pubByCentre' ORDER BY a.name;
SELECT filtername, join_filterclause, join_unique_key FROM dbo.sysmergesubsetfilters;
