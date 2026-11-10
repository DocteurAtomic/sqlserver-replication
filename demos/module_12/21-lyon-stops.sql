-- instance: SQL02 (Lyon)
-- ci: skip (Windows only)
-- Clip 12.3: before a change that requires a quiet topology, the node must know that every
-- other node has received everything. Here Lyon cannot answer: the Distribution Agent that
-- carries Lyon's changes of m12_pubCourse to Paris is stopped.
--   sqlcmd -S SQL02 -E -C -I -i 21-lyon-stops.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_stop_job @job_name = @job;
