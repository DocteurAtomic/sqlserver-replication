#!/usr/bin/env bash
# Module 7, clip 7.2. Thresholds, alerts and jobs, on the distributor. The two families of
# replication alerts created with the distributor: the "Replication Warning" alerts of the
# thresholds, enabled, and the "Replication:" alerts of agent events, disabled. A latency above
# the default threshold of pubCatalog (30 s): the Distribution Agent stopped while 600 commands
# wait 35 s at least; the monitor shows the warning (2), the error log has nothing, the threshold
# having @shouldalert = 0. The threshold set to 10 s with @shouldalert = 1: the monitor writes
# message 14161 to the error log when it computes a latency above it, after the next late
# delivery (15 s), not when the threshold changes. Then the alert "Replication: agent
# failure" (14151) enabled, and a failure of the Distribution Agent provoked by taking
# PachaCatalog offline: the agent writes 14151 to the error log and to
# msdb.dbo.sysreplicationalerts, and the alert does not fire, the alert engine of SQL Server Agent
# being disabled on Linux (sqlagent.out). PachaCatalog back online, the agent recovers, the
# alert and the threshold are set back. Last, the replication jobs of the distributor, and what
# notifying an operator would need (Database Mail, not configured on the lab).
# Needs 00-setup.sh first.
# Usage: ./demos/module_07/02-alerts.sh     (with Podman: ENGINE=podman ./demos/module_07/02-alerts.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
monitor() {
    sql rpllab2 -d distribution -s '|' -Q "SET NOCOUNT ON;
        EXEC sys.sp_replmonitorhelpsubscription @publisher = N'rpllab1', @publication_type = 0;" \
    | awk -F'|' -v want="status warning subscriber_db publication latency latencythreshold monitorranking" '
        /^status\|/ { n = split(want, w, " "); for (i = 1; i <= NF; i++) col[$i] = i; hdr = 1
                      line = ""; for (j = 1; j <= n; j++) line = line (j > 1 ? " " : "") w[j]; print line; next }
        hdr && /^[0-9]/ { line = ""; for (j = 1; j <= n; j++) line = line (j > 1 ? " " : "") $(col[w[j]]); print line }'
}
wait_status() {  # status, timeout: calls the monitor until the subscription has this status
    local want=$1 timeout=${2:-60} i got
    for i in $(seq 1 "$timeout"); do
        got=$(monitor | awk 'NR == 2 { print $1 }')
        [ "$got" = "$want" ] && return 0
        sleep 1
    done
    echo "wait_status: the monitor returned status '$got' after ${timeout}s, expected '$want'" >&2
    return 1
}
thresholds() {
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        EXEC sys.sp_replmonitorhelppublicationthresholds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
             @publication = N'pubCatalog';"
}
errorlog() {  # lines of the error log of rpllab2 since a time, containing a string
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.xp_readerrorlog 0, 1, N'$2', NULL, '$1';" | cut -c1-230
}

echo "== rpllab2: the replication alerts"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT IIF(name LIKE N'Replication Warning%', N'threshold', N'event') AS family, message_id, enabled, occurrence_count, name
    FROM msdb.dbo.sysalerts WHERE name LIKE N'Replication%' ORDER BY family DESC, message_id;"

echo
echo "== rpllab2: the thresholds of pubCatalog, as the distributor creates them"
thresholds

late_delivery() {  # seconds: the Distribution Agent stopped while 600 commands wait at least that long
    echo "== rpllab2: the Distribution Agent stopped, 600 commands written on rpllab1, delivered $1 s late at least"
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
    wait_status 2 60
    w=$(now)
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
        BEGIN TRAN;
        UPDATE Course.Session SET Price = Price + 1 WHERE SessionId BETWEEN 1 AND 300;
        UPDATE Course.Session SET Price = Price - 1 WHERE SessionId BETWEEN 1 AND 300;
        COMMIT;"
    # The latency is the age of the transaction when it reaches the subscriber: the agent is
    # started again once the transaction is in the distribution database and has waited long
    # enough there.
    wait_for rpllab2 "SELECT SUM(UndelivCmdsInDistDB) FROM distribution.dbo.MSdistribution_status" 600 60
    wait_for rpllab2 "SELECT IIF(DATEDIFF(second, MIN(entry_time), GETDATE()) >= $1, 1, 0)
                      FROM distribution.dbo.MSrepl_transactions WHERE entry_time >= '$w'" 1 90
    m=$(now)
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
    wait_for rpllab2 "SELECT SUM(UndelivCmdsInDistDB) FROM distribution.dbo.MSdistribution_status" 0 120
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT TOP (1) time, delivery_latency, LEFT(comments, 70) AS comments FROM dbo.MSdistribution_history
        WHERE comments LIKE N'%command(s) were delivered%' ORDER BY time DESC;"
}

echo
late_delivery 35
echo "-- the monitor, default threshold (30 s, shouldalert 0)"
monitor
echo "-- error log of rpllab2 since $m, message 14161"
errorlog "$m" "The threshold [latency"

echo
echo "== rpllab2: the latency threshold set to 10 s, with an alert"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorchangepublicationthreshold @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @thresholdmetricname = N'latency', @value = 10, @shouldalert = 1;" | cut -c1-230
thresholds
echo "-- the monitor, threshold 10 s, shouldalert 1, before a new delivery"
monitor
late_delivery 15
echo "-- the monitor, threshold 10 s, shouldalert 1, after the late delivery"
monitor
echo "-- error log of rpllab2 since $m, message 14161"
errorlog "$m" "The threshold [latency"
sql rpllab2 -Q "SET NOCOUNT ON; SELECT name, enabled, occurrence_count FROM msdb.dbo.sysalerts WHERE message_id = 14161;"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorchangepublicationthreshold @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @thresholdmetricname = N'latency', @value = 30, @shouldalert = 0;" | cut -c1-230

echo
echo "== rpllab2: the alert Replication: agent failure enabled"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_alert @name = N'Replication: agent failure', @enabled = 1;
    SELECT name, message_id, enabled, occurrence_count FROM msdb.dbo.sysalerts WHERE message_id = 14151;"
m=$(now)
echo "== rpllab3: PachaCatalog offline ($m)"
sql rpllab3 -Q "SET NOCOUNT ON; ALTER DATABASE PachaCatalog SET OFFLINE WITH ROLLBACK IMMEDIATE;"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE time >= '$m' AND runstatus = 6" 1 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (2) time, runstatus, LEFT(comments, 90) AS comments FROM dbo.MSdistribution_history
    WHERE time >= '$m' ORDER BY time DESC, timestamp DESC;
    SELECT time, error_code, LEFT(error_text, 90) AS error_text FROM dbo.MSrepl_errors WHERE time >= '$m' ORDER BY time, id;"
echo "-- error log of rpllab2 since $m, message 14151"
errorlog "$m" "14151"
errorlog "$m" "agent rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1 failed"
echo "-- msdb.dbo.sysreplicationalerts, written by the agent"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT alert_id, status, agent_type, alert_error_code, time, subscriber, subscriber_db
    FROM msdb.dbo.sysreplicationalerts WHERE time >= '$m' ORDER BY alert_id;"
echo "-- the alert"
sql rpllab2 -Q "SET NOCOUNT ON; SELECT name, enabled, occurrence_count, last_occurrence_date, last_occurrence_time
    FROM msdb.dbo.sysalerts WHERE message_id = 14151;"
echo "-- SQL Server Agent at its start (sqlagent.out)"
$engine exec rpllab2 cat /var/opt/mssql/log/sqlagent.out | iconv -f UTF-16LE -t UTF-8 | tr -d '\r' \
    | grep -E 'AlertEngine|alert\(s\) in the alert cache|Running SQL Server Agent cross-platform' | tail -3

echo
echo "== rpllab3: PachaCatalog online again"
m=$(now)
sql rpllab3 -Q "SET NOCOUNT ON; ALTER DATABASE PachaCatalog SET ONLINE;"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE time >= '$m' AND runstatus IN (3, 4)" 1 150
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (2) time, runstatus, LEFT(comments, 70) AS comments FROM dbo.MSdistribution_history ORDER BY time DESC, timestamp DESC;"
monitor
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_alert @name = N'Replication: agent failure', @enabled = 0;"

echo
echo "== rpllab2: the replication jobs of the distributor"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT j.name, j.enabled, s.freq_subday_type AS every_unit, s.freq_subday_interval AS every, LEFT(js.command, 60) AS command
    FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    JOIN msdb.dbo.sysjobsteps js ON js.job_id = j.job_id AND js.step_id = 1
    LEFT JOIN msdb.dbo.sysjobschedules x ON x.job_id = j.job_id LEFT JOIN msdb.dbo.sysschedules s ON s.schedule_id = x.schedule_id
    WHERE (c.name LIKE N'REPL-%' AND c.name NOT IN (N'REPL-Distribution', N'REPL-LogReader', N'REPL-Snapshot'))
       OR j.name = N'Monitor and sync replication agent jobs'
    ORDER BY j.name;"
echo "== rpllab2: operators and Database Mail"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM msdb.dbo.sysoperators) AS operators,
           (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) AS mail_profiles,
           (SELECT COUNT(*) FROM msdb.dbo.sysnotifications) AS notifications;"
