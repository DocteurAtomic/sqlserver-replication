#!/usr/bin/env bash
# Module 9, clip 9.3. The distribution database during and after the closing. The memory of the
# distributor rpllab2 (the container limit, what the instance sees, its target and total
# memory, the sessions of the replication agents). The closing of m09_Billing played while the
# Distribution Agent is stopped (a slow subscription): the size of the distribution database
# and its commands, then the job "Distribution clean up: distribution" (its procedure,
# sp_MSdistribution_cleanup, called with the parameters of the job) keeps the 200,000 commands
# the subscription has not received. The agent started, the commands delivered: the same
# cleanup removes them, timed, while the locks of its session are sampled. Then m09_pubBilling
# switched to immediate_sync = 1: a closing delivered, and the cleanup keeps its commands, for
# max_distretention; immediate_sync set back to 0, the next cleanup removes them.
# Measured on 11 November 2026: the cleanup keeps the last transaction delivered to each
# subscription (its 100 commands, or the 200,000 of a closing made in one transaction) until a
# newer one arrives. The data file of distribution keeps the size it grew to.
# Needs 00-setup.sh first (01 and 02 may have run). About four minutes.
# Usage: ./demos/module_09/03-distribution.sh     (with Podman: ENGINE=podman ./demos/module_09/03-distribution.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_09/lib.sh

size() {  # the distribution database: files, commands, transactions
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT (SELECT SUM(size) * 8 / 1024 FROM sys.database_files WHERE type = 0) AS data_mb,
               (SELECT CAST(FILEPROPERTY(name, 'SpaceUsed') AS bigint) * 8 / 1024 FROM sys.database_files WHERE type = 0) AS data_used_mb,
               (SELECT SUM(size) * 8 / 1024 FROM sys.database_files WHERE type = 1) AS log_mb,
               (SELECT COUNT_BIG(*) FROM dbo.MSrepl_commands) AS commands,
               (SELECT COUNT_BIG(*) FROM dbo.MSrepl_transactions) AS transactions;"
}
cleanup() {  # the procedure of the job Distribution clean up, with the parameters of its step
    local s
    s=$(date +%s%N)
    sql rpllab2 -d distribution -Q "SET CONTEXT_INFO 0x0909; EXEC dbo.sp_MSdistribution_cleanup @min_distretention = 0, @max_distretention = 72;" \
        | grep -E 'Removed|Deleted [1-9]' || true
    echo "-- cleanup: $(( ($(date +%s%N) - s) / 1000000 )) ms, sqlcmd included"
}
closing() {  # the closing of m09_Billing, 2,000 transactions of 100 lines
    local cur new
    cur=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT Status FROM m09_Billing.dbo.InvoiceLine WHERE LineId = 1;" | tr -d '[:space:]')
    new=$([ "$cur" = OPEN ] && echo CLOSED || echo OPEN)
    sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
        DECLARE @i int = 0;
        WHILE @i < 2000
        BEGIN
            UPDATE dbo.InvoiceLine SET Status = '$new' WHERE LineId > @i * 100 AND LineId <= (@i + 1) * 100;
            SET @i += 1;
        END;"
    echo "rpllab1: closing, 200000 lines set to $new"
    status=$new
}
delivered() {  # wait until the subscriber has the closing
    wait_for rpllab3 "SELECT COUNT(*) FROM m09_Billing.dbo.InvoiceLine WHERE Status = '$status'" 200000 300
    wait_for rpllab2 "SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent" 0 300
    echo "rpllab3: the 200000 lines are $status, nothing pending"
}

echo "== rpllab2: the memory of the distributor"
$engine stats --no-stream --format '{{.Name}} {{.MemUsage}}' rpllab2
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT physical_memory_kb / 1024 AS seen_by_instance_mb, committed_target_kb / 1024 AS target_mb, committed_kb / 1024 AS committed_mb
    FROM sys.dm_os_sys_info;
    SELECT COUNT(*) AS agent_sessions FROM sys.dm_exec_sessions WHERE program_name LIKE N'rpllab1-%' OR program_name LIKE N'RPLLAB1-%' OR program_name LIKE N'Repl-%';"

echo
echo "== rpllab2: the distribution database before the closing"
cleanup > /dev/null
size

echo
echo "== the closing while the Distribution Agent is stopped"
stop_agent
closing
wait_for rpllab2 "SELECT IIF(ISNULL(SUM(UndelivCmdsInDistDB), 0) >= 200000, 1, 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent" 1 300
echo "rpllab2: $(pending) commands pending"
size
$engine stats --no-stream --format '{{.Name}} {{.MemUsage}}' rpllab2
echo "-- Distribution clean up, subscription behind"
cleanup
size

echo
echo "== the Distribution Agent started, the closing delivered"
start_agent
delivered
size
echo "-- Distribution clean up, everything delivered, with the locks of its session sampled"
locks=$(mktemp)
( for i in $(seq 1 40); do
      sql rpllab2 -h -1 -Q "SET NOCOUNT ON;
          SELECT CONCAT(l.resource_type, N' ', l.request_mode, N' ',
                        ISNULL(OBJECT_NAME(IIF(l.resource_type = N'OBJECT', l.resource_associated_entity_id, p.object_id), l.resource_database_id), N'-'),
                        N' ', COUNT(*))
          FROM sys.dm_tran_locks l JOIN sys.dm_exec_requests r ON r.session_id = l.request_session_id
          LEFT JOIN distribution.sys.partitions p ON p.hobt_id = l.resource_associated_entity_id
          WHERE SUBSTRING(r.context_info, 1, 2) = 0x0909 AND l.resource_database_id = DB_ID(N'distribution')
          GROUP BY l.resource_type, l.request_mode,
                   ISNULL(OBJECT_NAME(IIF(l.resource_type = N'OBJECT', l.resource_associated_entity_id, p.object_id), l.resource_database_id), N'-');" 2>/dev/null | tr -d '\r' | sed '/^$/d'
      sleep 0.25
  done > "$locks" ) &
sampler=$!
cleanup
wait $sampler || true
echo "-- locks held by the cleanup, as sampled (type, mode, object, count; the largest count of each)"
sort "$locks" | awk '{k=$1" "$2" "$3; if ($4+0 > m[k]) m[k]=$4+0} END {for (k in m) print k, m[k]}' | sort
rm -f "$locks"
size

echo
echo "== m09_pubBilling with immediate_sync = 1"
sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
    EXEC sys.sp_changepublication @publication = N'm09_pubBilling', @property = N'immediate_sync', @value = N'true',
         @force_invalidate_snapshot = 1;
    SELECT name, immediate_sync FROM dbo.syspublications WHERE name = N'm09_pubBilling';"
closing
delivered
echo "-- Distribution clean up, everything delivered, immediate_sync = 1"
cleanup
size
echo "-- immediate_sync set back to 0"
sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
    EXEC sys.sp_changepublication @publication = N'm09_pubBilling', @property = N'immediate_sync', @value = N'false';
    SELECT name, immediate_sync FROM dbo.syspublications WHERE name = N'm09_pubBilling';"
cleanup
size
