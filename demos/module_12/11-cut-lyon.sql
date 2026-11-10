-- instance: SQL02 (Lyon)
-- ci: skip (Windows only)
-- Clip 12.2: the link from Lyon to Paris is cut (the Distribution Agent of m12_pubCourse is
-- stopped), and Lyon changes the price of the same course, a few seconds later.
--   sqlcmd -S SQL02 -E -C -I -i 11-cut-lyon.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname = (SELECT name FROM m12_distribution.dbo.MSdistribution_agents
                        WHERE publication = N'm12_pubCourse' AND subscriber_db = N'm12_catalog');
EXEC msdb.dbo.sp_stop_job @job_name = @job;
UPDATE Catalog.Course SET Price = 1750.00 WHERE CourseId = 4;
SELECT @@SERVERNAME AS node, CourseId, Title, Price FROM Catalog.Course WHERE CourseId = 4;
