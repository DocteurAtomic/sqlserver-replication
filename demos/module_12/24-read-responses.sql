-- instance: SQL01 (Paris)
-- ci: skip (Windows only: run it after 23-lyon-restarts.sql on SQL02)
-- Clip 12.3: the answer of Lyon to the last request (one minute at most), then what the
-- topology keeps: the requests, the last transaction received from each node (MSpeer_lsns)
-- and the originators known to the Distributor (MSrepl_originators).
--   sqlcmd -S SQL01 -E -C -I -i 24-read-responses.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @request_id int = (SELECT MAX(id) FROM dbo.MSpeer_request), @i int = 0;
WHILE @i < 120 AND NOT EXISTS (SELECT 1 FROM dbo.MSpeer_response WHERE request_id = @request_id AND received_date IS NOT NULL)
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
EXEC sys.sp_helppeerresponses @request_id = @request_id;
SELECT id, publication, sent_date, description FROM dbo.MSpeer_request ORDER BY id;
SELECT originator, originator_db, originator_publication, originator_lsn
FROM dbo.MSpeer_lsns ORDER BY originator_publication;
SELECT id, publisher_database_id, srvname, dbname, publication_id, dbversion
FROM m12_distribution.dbo.MSrepl_originators ORDER BY id;
