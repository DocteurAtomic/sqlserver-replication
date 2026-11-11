-- instance: rpllab2
-- Exercise of module 7, solution, part 1: the morning query. On the distributor, a database of
-- the exercise, ex_monitor, with dbo.ReplHealth: one row per subscription of the distributor,
-- read from the tables of the distribution database (sp_replmonitorhelpsubscription cannot be
-- captured by INSERT ... EXEC, it uses one itself: Msg 8164), and the table that keeps the
-- failures of the agents, filled by the job of part 2.
SET NOCOUNT ON;
CREATE DATABASE ex_monitor;
GO
USE ex_monitor;
GO
CREATE TABLE dbo.AgentFailure (
    alert_id      int            NOT NULL PRIMARY KEY,   -- msdb.dbo.sysreplicationalerts.alert_id
    time          datetime       NOT NULL,
    agent_type    int            NOT NULL,               -- 1 snapshot, 2 log reader, 3 distribution
    subscriber_db sysname        NULL,
    error_text    nvarchar(4000) NULL,
    seen_at       datetime       NOT NULL DEFAULT GETDATE());
GO
-- Columns, in this order: publication, subscriber_db, agent_status (the runstatus of the last line
-- of the agent's history: 1 start, 2 succeed, 3 in progress, 4 idle, 5 retry, 6 fail),
-- latency_seconds (of the last delivery) and pending_commands (not yet delivered).
CREATE PROCEDURE dbo.ReplHealth
AS
SET NOCOUNT ON;
SELECT a.publication, a.subscriber_db,
       h.runstatus AS agent_status,
       d.delivery_latency / 1000 AS latency_seconds,
       ISNULL(p.pending, 0) AS pending_commands
FROM distribution.dbo.MSdistribution_agents AS a
OUTER APPLY (SELECT TOP (1) runstatus FROM distribution.dbo.MSdistribution_history
             WHERE agent_id = a.id ORDER BY time DESC, timestamp DESC) AS h
OUTER APPLY (SELECT TOP (1) delivery_latency FROM distribution.dbo.MSdistribution_history
             WHERE agent_id = a.id AND delivered_commands > 0 ORDER BY time DESC, timestamp DESC) AS d
OUTER APPLY (SELECT SUM(UndelivCmdsInDistDB) AS pending FROM distribution.dbo.MSdistribution_status
             WHERE agent_id = a.id) AS p
WHERE a.subscriber_db <> N'virtual'
ORDER BY a.publication, a.subscriber_db;
GO
EXEC dbo.ReplHealth;
