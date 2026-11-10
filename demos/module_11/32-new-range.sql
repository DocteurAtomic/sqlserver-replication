-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run 31-exhaust-range.sql on the subscriber first)
-- Clip 11.5: Lille synchronizes: it uploads its 200 lines and receives new ranges.
--   sqlcmd -S SQL01 -E -C -I -i 32-new-range.sql
SET NOCOUNT ON;
USE m11_pacha;
EXEC dbo.m11_sync @subscriber_db = N'm11_lille', @publication = N'm11_pubByCentre';
SELECT s.db_name AS node, r.range_begin, r.range_end, r.next_range_begin, r.next_range_end, r.max_used
FROM dbo.MSmerge_identity_range AS r
JOIN dbo.sysmergesubscriptions AS s ON s.subid = r.subid
WHERE s.db_name = N'm11_lille';
