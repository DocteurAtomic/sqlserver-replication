-- instance: SQL01, then SQL02 (the property is set on every node)
-- ci: skip (Windows only: run it after 12-reconnect.sql on both nodes)
-- Clip 12.2: the way out that Learn gives besides restoring a node from a backup: the
-- Distribution Agent may now apply the change and log the conflict instead of stopping
-- (p2p_continue_onconflict). The agent that delivers to a node reads the setting of that node:
-- set it on both before 14-restart-course.sql.
--   sqlcmd -S SQL01 -E -C -I -i 13-continue-onconflict.sql
SET NOCOUNT ON;
USE m12_catalog;
EXEC sys.sp_changepublication @publication = N'm12_pubCourse',
     @property = N'p2p_continue_onconflict', @value = N'true';
SELECT @@SERVERNAME AS node, name, options, (options & 16) / 16 AS continue_onconflict
FROM dbo.syspublications ORDER BY name;
