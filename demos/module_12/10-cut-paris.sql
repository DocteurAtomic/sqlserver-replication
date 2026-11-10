-- instance: SQL01 (Paris)
-- ci: skip (Windows only)
-- Clip 12.2: the link from Paris to Lyon is cut (the Distribution Agent of m12_pubCourse is
-- stopped), and Paris changes the price of course 4.
--   sqlcmd -S SQL01 -E -C -I -i 10-cut-paris.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_stop_job @job_name = @job;
UPDATE Catalog.Course SET Price = 1700.00 WHERE CourseId = 4;
SELECT @@SERVERNAME AS node, CourseId, Title, Price FROM Catalog.Course WHERE CourseId = 4;
