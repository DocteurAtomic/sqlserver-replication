#!/usr/bin/env bash
# Module 8, clip 8.1. The Log Reader Agent stopped, on the database of the module, m08_Journal,
# never on PachadataTraining. The state of the log first (log_reuse_wait_desc, size and use,
# active virtual log files). The job of the Log Reader Agent disabled (so that nothing starts it
# again) and stopped; 4 096 rows written on rpllab1, a checkpoint, then a log backup: SQL
# Server says why it did not truncate the log, and log_reuse_wait_desc becomes REPLICATION. Then
# 60 000 rows more: the log grows, and a second log backup changes nothing. sp_repltrans lists
# the transactions not yet read by the agent, DBCC OPENTRAN gives the oldest LSN not
# distributed. The job enabled and started again: sp_repltrans empty, the rows on rpllab3, and
# the next log backup truncates; the file keeps its size.
# Needs 00-setup.sh first.
# Usage: ./demos/module_08/01-log-reader.sh     (with Podman: ENGINE=podman ./demos/module_08/01-log-reader.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSlogreader_agents WHERE publisher_db = N'm08_Journal';" | tr -d '[:space:]')
logstate() {
    sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON;
        SELECT d.log_reuse_wait_desc, CAST(u.total_log_size_in_bytes / 1048576.0 AS decimal(9, 1)) AS log_mb,
               CAST(u.used_log_space_in_percent AS decimal(5, 1)) AS used_percent,
               (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID()) WHERE vlf_active = 1) AS active_vlf,
               (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf
        FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u WHERE d.name = N'm08_Journal';"
}
logbackup() {
    sql rpllab1 -Q "SET NOCOUNT ON; BACKUP LOG m08_Journal TO DISK = N'/var/opt/mssql/data/m08_Journal.trn' WITH INIT;" 2>&1 | grep -v '^Processed'
}
repltrans() {  # the transactions of m08_Journal marked for replication and not yet read
    sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON;
        CREATE TABLE #t (xdesid varbinary(10), xact_seqno varbinary(10));
        INSERT #t EXEC sys.sp_repltrans;
        SELECT COUNT(*) AS transactions_not_read, CONVERT(varchar(22), MIN(xact_seqno), 1) AS first_seqno,
               CONVERT(varchar(22), MAX(xact_seqno), 1) AS last_seqno FROM #t;"
}
running() {
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}

echo "== rpllab1: the log of m08_Journal, the Log Reader Agent running ($job)"
logbackup
logstate

echo
echo "== rpllab2: the Log Reader Agent disabled and stopped"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 0; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
wait_for rpllab2 "$(running)" 0 60
echo "== rpllab1: 4 096 rows, a checkpoint"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON; INSERT dbo.Event (Body) SELECT TOP (4096) 'clip 8.1' FROM PachadataTraining.Tools.Number; CHECKPOINT;"
logstate
echo "-- a log backup"
logbackup
logstate

echo
echo "== rpllab1: 60 000 rows more, in three transactions"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON;
    INSERT dbo.Event (Body) SELECT TOP (20000) 'clip 8.1' FROM PachadataTraining.Tools.Number;
    INSERT dbo.Event (Body) SELECT TOP (20000) 'clip 8.1' FROM PachadataTraining.Tools.Number;
    INSERT dbo.Event (Body) SELECT TOP (20000) 'clip 8.1' FROM PachadataTraining.Tools.Number;"
logstate
echo "-- a log backup"
logbackup
logstate
echo "-- what waits in the log: sp_repltrans, DBCC OPENTRAN"
repltrans
sql rpllab1 -Q "DBCC OPENTRAN (N'm08_Journal');" | grep -E 'LSN|Replicated'
echo "-- the subscriber"
sql rpllab1 -d m08_Journal -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'rpllab1: ', COUNT(*), N' rows in dbo.Event') FROM dbo.Event;"
sql rpllab3 -d m08_Journal -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'rpllab3: ', COUNT(*), N' rows in dbo.Event') FROM dbo.Event;"

echo
echo "== rpllab2: the Log Reader Agent enabled and started"
s=$(date +%s)
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 1; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
wait_for rpllab1 "DECLARE @t TABLE (a varbinary(10), b varbinary(10)); INSERT @t EXEC m08_Journal.sys.sp_repltrans; SELECT COUNT(*) FROM @t" 0 180
echo "sp_repltrans empty after $(( $(date +%s) - s )) s"
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m08_Journal.dbo.Event" | tr -d '[:space:]')
wait_for rpllab3 "SELECT COUNT(*) FROM m08_Journal.dbo.Event" "$want" 300
echo "rpllab3: $want rows in dbo.Event after $(( $(date +%s) - s )) s"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.time, LEFT(h.comments, 70) AS comments FROM dbo.MSlogreader_history h
    JOIN dbo.MSlogreader_agents a ON a.id = h.agent_id WHERE a.publisher_db = N'm08_Journal'
      AND h.comments LIKE N'%command(s) were delivered%' ORDER BY h.time DESC;"
logstate
echo "-- a log backup"
logbackup
logstate
