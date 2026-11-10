-- instance: SQL01, then SQL02
-- ci: skip (Windows only: run it after 14-restart-course.sql on both nodes)
-- Clip 12.2: the last step of Learn's procedure: the agents stop again at the next conflict,
-- once the nodes agree. The price of course 4 is read on each node.
--   sqlcmd -S SQL01 -E -C -I -i 15-continue-off.sql
SET NOCOUNT ON;
USE m12_catalog;
EXEC sys.sp_changepublication @publication = N'm12_pubCourse',
     @property = N'p2p_continue_onconflict', @value = N'false';
SELECT @@SERVERNAME AS node, CourseId, Price FROM Catalog.Course WHERE CourseId = 4;
