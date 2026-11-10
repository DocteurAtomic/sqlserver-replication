-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: needs the merge publication of 01-publish.sql)
-- Clip 11.1: starts the Snapshot Agent of m11_pubCentres and waits for the snapshot, at most
-- three minutes, by reading the agent history (a bounded loop, never a fixed delay).
--   sqlcmd -S SQL01 -E -C -I -i 02-snapshot.sql
SET NOCOUNT ON;
USE m11_pacha;
DECLARE @start datetime = GETDATE(), @done int = 0, @i int = 0;
EXEC sys.sp_startpublication_snapshot @publication = N'm11_pubCentres';
WHILE @done = 0 AND @i < 180
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @i += 1;
    SELECT @done = COUNT(*) FROM m11_distribution.dbo.MSsnapshot_history AS h
    JOIN m11_distribution.dbo.MSsnapshot_agents AS a ON a.id = h.agent_id
    WHERE a.publication = N'm11_pubCentres' AND h.runstatus IN (2, 6) AND h.time >= @start;
END;
SELECT TOP (3) h.time, h.runstatus, LEFT(h.comments, 120) AS comments
FROM m11_distribution.dbo.MSsnapshot_history AS h
JOIN m11_distribution.dbo.MSsnapshot_agents AS a ON a.id = h.agent_id
WHERE a.publication = N'm11_pubCentres' ORDER BY h.timestamp DESC;
SELECT snapshot_ready FROM dbo.sysmergepublications WHERE name = N'm11_pubCentres';
