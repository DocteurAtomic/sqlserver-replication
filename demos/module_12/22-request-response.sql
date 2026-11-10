-- instance: SQL01 (Paris)
-- ci: skip (Windows only: run it after 21-lyon-stops.sql on SQL02)
-- Clip 12.3: Paris asks every node of m12_pubCourse to answer (sp_requestpeerresponse). The
-- request travels like a transaction; the answer comes back by Lyon's Log Reader and
-- Distribution Agents. The script waits 30 seconds for an answer (received_date), then lists the answers.
--   sqlcmd -S SQL01 -E -C -I -i 22-request-response.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @request_id int, @i int = 0;
EXEC sys.sp_requestpeerresponse @publication = N'm12_pubCourse',
     @description = N'Before changing the schema of Course', @request_id = @request_id OUTPUT;
WHILE @i < 60 AND NOT EXISTS (SELECT 1 FROM dbo.MSpeer_response WHERE request_id = @request_id AND received_date IS NOT NULL)
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT @request_id AS request_id, @i / 2 AS waited_seconds;
EXEC sys.sp_helppeerresponses @request_id = @request_id;
