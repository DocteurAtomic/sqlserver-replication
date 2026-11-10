-- instance: SQL02 (Lyon)
-- ci: skip (Windows only)
-- Clip 12.3: Lyon's Distribution Agent of m12_pubCourse starts again.
--   sqlcmd -S SQL02 -E -C -I -i 23-lyon-restarts.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_start_job @job_name = @job;
