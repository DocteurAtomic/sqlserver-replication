-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the subscriptions of 23-subscribe-by-centre.sql)
-- Clip 11.5: the identity ranges the publisher handed out for Attendance, and the check
-- constraint that guards its own ranges.
--   sqlcmd -S SQL01 -E -C -I -i 30-identity-ranges.sql
SET NOCOUNT ON;
USE m11_pacha;
SELECT s.db_name AS node, r.range_begin, r.range_end, r.next_range_begin, r.next_range_end, r.max_used
FROM dbo.MSmerge_identity_range AS r
JOIN dbo.sysmergesubscriptions AS s ON s.subid = r.subid
JOIN dbo.sysmergearticles AS a ON a.artid = r.artid AND a.pubid = (SELECT pubid FROM dbo.sysmergepublications WHERE name = N'm11_pubByCentre')
ORDER BY r.range_begin;
SELECT name, definition FROM sys.check_constraints WHERE name LIKE N'repl[_]identity[_]range%';
SELECT IDENT_CURRENT('Training.Attendance') AS ident_current;
