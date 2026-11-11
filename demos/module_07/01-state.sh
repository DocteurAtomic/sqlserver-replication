#!/usr/bin/env bash
# Module 7, clip 7.1. Every morning, without opening a monitor: are the subscribers up to date?
# On the distributor, the procedures Replication Monitor itself calls: sp_replmonitorhelppublisher
# and sp_replmonitorhelpsubscription (status, warning, latency of each subscription), then the
# history the agents write in the distribution database (MSlogreader_history,
# MSdistribution_history, MSrepl_errors) and the commands not yet delivered
# (MSdistribution_status, sp_replmonitorsubscriptionpendingcmds). Then the same reading while
# the Distribution Agent is stopped and the publisher writes 600 commands (300 prices + 1, then
# - 1, in one transaction: the data ends as it was), and after it is started again. Last, a
# login of the role replmonitor in the distribution database (exercise 20 of the support): what
# it can read, and what it is refused.
# Needs 00-setup.sh first.
# Usage: ./demos/module_07/01-state.sh     (with Podman: ENGINE=podman ./demos/module_07/01-state.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1
monitor() {  # sp_replmonitorhelpsubscription, the columns that answer the question of the morning
    sql rpllab2 -d distribution -s '|' -Q "SET NOCOUNT ON;
        EXEC sys.sp_replmonitorhelpsubscription @publisher = N'rpllab1', @publication_type = 0;" \
    | awk -F'|' -v want="status warning subscriber_db publication latency latencythreshold agentnotrunning timetoexpiration last_distsync monitorranking" '
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
pending() {
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
             @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0;"
}
undelivered() {  # MSdistribution_status, one row per article and agent: commands kept in distribution
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT a.name AS agent, SUM(s.UndelivCmdsInDistDB) AS undelivered, SUM(s.DelivCmdsInDistDB) AS delivered_kept
        FROM dbo.MSdistribution_status s JOIN dbo.MSdistribution_agents a ON a.id = s.agent_id
        GROUP BY a.name;"
}

echo "== rpllab2: the publishers of this distributor"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; EXEC sys.sp_replmonitorhelppublisher;"
echo
echo "== rpllab2: the subscriptions (sp_replmonitorhelpsubscription)"
monitor
echo
echo "== rpllab2: the last lines written by the two agents"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (3) N'logreader' AS agent, time, runstatus, delivery_latency, LEFT(comments, 70) AS comments
    FROM dbo.MSlogreader_history ORDER BY time DESC;
    SELECT TOP (3) N'distribution' AS agent, time, runstatus, delivery_latency, LEFT(comments, 70) AS comments
    FROM dbo.MSdistribution_history ORDER BY time DESC;"
echo
echo "== rpllab2: the errors kept in distribution (MSrepl_errors)"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; SELECT COUNT(*) AS errors, MAX(time) AS last_error FROM dbo.MSrepl_errors;"
echo
echo "== rpllab2: commands not yet delivered"
undelivered
pending

echo
echo "== rpllab2: the Distribution Agent stopped"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
# The monitor returns what it keeps in MSreplication_monitordata, which its own calls refresh: on
# the first run of this script, it still returned 3 (in progress) just after the stop. The
# script calls it until it returns 2 (stopped), a few seconds.
wait_status 2 60
echo "== rpllab1: 300 prices + 1, then - 1, in one transaction"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRAN;
    UPDATE Course.Session SET Price = Price + 1 WHERE SessionId BETWEEN 1 AND 300;
    UPDATE Course.Session SET Price = Price - 1 WHERE SessionId BETWEEN 1 AND 300;
    COMMIT;
    SELECT COUNT(*) AS sessions_changed_twice FROM Course.Session WHERE SessionId BETWEEN 1 AND 300;"
wait_for rpllab2 "SELECT SUM(UndelivCmdsInDistDB) FROM distribution.dbo.MSdistribution_status" 600 60
echo
echo "== rpllab2: what the morning query sees now"
monitor
undelivered
pending
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (2) time, runstatus, LEFT(comments, 70) AS comments FROM dbo.MSdistribution_history ORDER BY time DESC, timestamp DESC;"

echo
echo "== rpllab2: the Distribution Agent started again"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
wait_for rpllab2 "SELECT SUM(UndelivCmdsInDistDB) FROM distribution.dbo.MSdistribution_status" 0 120
monitor
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) time, runstatus, delivery_latency, LEFT(comments, 70) AS comments FROM dbo.MSdistribution_history
    WHERE comments LIKE N'%command(s) were delivered%' ORDER BY time DESC;"

echo
echo "== rpllab2: a login of the role replmonitor"
sql rpllab2 -Q "SET NOCOUNT ON;
    CREATE LOGIN m07_monitor WITH PASSWORD = N'Monitor-2026!lab', CHECK_POLICY = OFF;
    USE distribution;
    CREATE USER m07_monitor FOR LOGIN m07_monitor;
    ALTER ROLE replmonitor ADD MEMBER m07_monitor;
    SELECT r.name AS role, m.name AS member FROM sys.database_role_members x
    JOIN sys.database_principals r ON r.principal_id = x.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = x.member_principal_id WHERE m.name = N'm07_monitor';"
as_monitor() {  # one statement under the login m07_monitor; an error is shown, not fatal
    echo "-- as m07_monitor: $1"
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON; EXECUTE AS LOGIN = N'm07_monitor'; $1; REVERT;" 2>&1 | cut -c1-200 || true
}
as_monitor "EXEC sys.sp_replmonitorhelppublisher"
as_monitor "SELECT COUNT(*) AS rows_read FROM dbo.MSdistribution_history"
as_monitor "SELECT COUNT(*) AS rows_read FROM dbo.MSrepl_errors"
as_monitor "EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining', @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0"
as_monitor "EXEC msdb.dbo.sp_stop_job @job_name = N'$job'"
echo "-- as m07_monitor: EXEC sys.sp_replmonitorhelpsubscription"
sql rpllab2 -d distribution -s '|' -Q "SET NOCOUNT ON; EXECUTE AS LOGIN = N'm07_monitor';
    EXEC sys.sp_replmonitorhelpsubscription @publisher = N'rpllab1', @publication_type = 0; REVERT;" \
    | grep -c '^[0-9]' | sed 's/^/subscription rows returned: /'
