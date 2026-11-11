#!/usr/bin/env bash
# Module 7, clip 7.3. The performance counters of the replication agents, read on Linux through
# sys.dm_os_performance_counters (perfmon is a Windows tool). On the distributor, one counter
# instance per agent, named after its job: Logreader:, Dist: and Snapshot: counters, plus the
# number of agents running by type. The ".../sec" counters are cumulative values (cntr_type
# 272696576): a rate takes two readings and a division. A burst of 2 000 commands on rpllab1
# (1 000 prices + 1, then - 1, in one transaction: the data ends as it was), read before and
# after. The same counters on the publisher and the subscriber: none, the agents of a push
# subscription with a remote distributor run on the distributor. Last, the morning reading of
# clip 7.1 once more: status, warning and latency of the subscription, and its pending commands.
# Needs 00-setup.sh first.
# Usage: ./demos/module_07/03-counters.sh     (with Podman: ENGINE=podman ./demos/module_07/03-counters.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
counters() {
    sql $1 -Q "SET NOCOUNT ON;
        SELECT RTRIM(object_name) AS object_name, RTRIM(counter_name) AS counter_name, RTRIM(instance_name) AS instance_name,
               cntr_value, cntr_type
        FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%:Replication%' ORDER BY object_name, instance_name, counter_name;"
}
reading() {  # one reading of the counters of the Distribution Agent, with the time it was taken
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON;
        SELECT CONCAT(CONVERT(varchar(23), SYSDATETIME(), 121), N' ',
               MAX(IIF(counter_name LIKE N'Dist:Delivered Cmds/sec%', cntr_value, NULL)), N' ',
               MAX(IIF(counter_name LIKE N'Dist:Delivered Trans/sec%', cntr_value, NULL)), N' ',
               MAX(IIF(counter_name LIKE N'Dist:Delivery Latency%', cntr_value, NULL)))
        FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%:Replication Dist.%';" | tr -d '\r' | sed '/^$/d'
}

echo "== rpllab2: the replication counters of the distributor"
counters rpllab2
echo "-- the agent jobs actually running, for comparison with Replication Agents Running"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT c.name AS category, COUNT(*) AS jobs_running
    FROM msdb.dbo.sysjobactivity ja JOIN msdb.dbo.sysjobs j ON j.job_id = ja.job_id
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
      AND ja.start_execution_date IS NOT NULL AND ja.stop_execution_date IS NULL AND c.name LIKE N'REPL-%'
    GROUP BY c.name;"
echo
echo "== rpllab1 and rpllab3: the same counters on the publisher and the subscriber"
for n in rpllab1 rpllab3; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$n: ', COUNT(*), N' replication counters')
        FROM sys.dm_os_performance_counters WHERE object_name LIKE N'%:Replication%';"
done

echo
echo "== rpllab2: a reading, 2 000 commands on rpllab1, a second reading"
echo "time delivered_cmds delivered_trans latency_ms"
r1=$(reading); echo "$r1"
m=$(echo "$r1" | cut -d' ' -f1,2)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRAN;
    UPDATE Course.Session SET Price = Price + 1 WHERE SessionId BETWEEN 1 AND 1000;
    UPDATE Course.Session SET Price = Price - 1 WHERE SessionId BETWEEN 1 AND 1000;
    COMMIT;"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history
                  WHERE comments LIKE N'%with 2000 command(s) were delivered.' AND time >= '$m'" 1 120
r2=$(reading); echo "$r2"
echo "$r1 $r2" | awk '{
    split($2, a, ":"); split($7, b, ":"); s = (b[1] * 3600 + b[2] * 60 + b[3]) - (a[1] * 3600 + a[2] * 60 + a[3]);
    printf "difference: %d commands, %d transactions in %.1f s, so %.0f commands per second over the interval\n",
           $8 - $3, $9 - $4, s, ($8 - $3) / s }'
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) time, delivery_latency, delivery_rate, LEFT(comments, 70) AS comments FROM dbo.MSdistribution_history
    WHERE comments LIKE N'%with 2000 command(s) were delivered.' ORDER BY time DESC;"

echo
echo "== rpllab2: the morning reading, after everything"
sql rpllab2 -d distribution -s '|' -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorhelpsubscription @publisher = N'rpllab1', @publication_type = 0;" \
| awk -F'|' -v want="status warning subscriber_db publication latency latencythreshold timetoexpiration last_distsync monitorranking" '
    /^status\|/ { n = split(want, w, " "); for (i = 1; i <= NF; i++) col[$i] = i; hdr = 1
                  line = ""; for (j = 1; j <= n; j++) line = line (j > 1 ? " " : "") w[j]; print line; next }
    hdr && /^[0-9]/ { line = ""; for (j = 1; j <= n; j++) line = line (j > 1 ? " " : "") $(col[w[j]]); print line }'
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0;"
