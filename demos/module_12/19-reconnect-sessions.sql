-- instance: SQL01, then SQL02 (each node restarts its own Distribution Agent)
-- ci: skip (Windows only: run it after 17 and 18)
-- Clip 12.2, last writer wins: the Distribution Agent of m12_pubSession starts again. With
-- p2p_continue_onconflict set at creation, it resolves the conflicts instead of stopping.
-- The script waits for a delivered change or an error (one minute at most), then reads the two
-- sessions here and the conflict table of Session.
--   sqlcmd -S SQL01 -E -C -I -i 19-reconnect-sessions.sql
SET NOCOUNT ON;
USE m12_catalog;
DECLARE @job sysname, @agent int, @start datetime = GETDATE(), @i int = 0;
SELECT @job = name, @agent = id FROM m12_distribution.dbo.MSdistribution_agents
WHERE publication = N'm12_pubSession' AND subscriber_db = N'm12_catalog';
EXEC msdb.dbo.sp_start_job @job_name = @job;
WHILE @i < 120 AND NOT EXISTS (
    SELECT 1 FROM m12_distribution.dbo.MSdistribution_history
    WHERE agent_id = @agent AND time >= @start AND (runstatus = 6 OR delivered_commands > 0))
BEGIN
    WAITFOR DELAY '00:00:00.500';
    SET @i += 1;
END;
SELECT TOP (1) runstatus, LEFT(comments, 120) AS comments FROM m12_distribution.dbo.MSdistribution_history
WHERE agent_id = @agent AND time >= @start ORDER BY time DESC, timestamp DESC;
SELECT @@SERVERNAME AS node, s.SessionId, s.Seats
FROM (VALUES (110), (121)) AS v(SessionId) LEFT JOIN Catalog.Session AS s ON s.SessionId = v.SessionId;
SELECT __$originator_id AS originator_id, __$origin_datasource AS origin, __$conflict_type AS conflict_type,
       __$is_winner AS is_winner, SessionId, Seats, __$sys_mw_cd_id AS last_write_time,
       __$reason_text AS reason_text
FROM dbo.conflict_Catalog_Session ORDER BY SessionId, __$row_id;
