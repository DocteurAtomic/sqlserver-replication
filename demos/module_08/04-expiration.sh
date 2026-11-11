#!/usr/bin/env bash
# ci: skip (waits more than an hour of real time for the distribution retention to expire)
# Module 8, clip 8.4. A subscription deactivated by the distribution retention. The retention
# of the distributor (max_distretention, in hours, for every publication of the distributor,
# 72 by default) set to 1: the Distribution Agent of m08_pubJournal disabled and stopped, 100
# rows written on rpllab1, then the script waits until these commands are older than the
# retention (61 minutes). Measured on 11 November 2026: the job "Distribution clean up:
# distribution" (every 10 minutes) ran for 1 h 48 min without deactivating the subscription, and
# the job "Expired subscription clean up" (daily, started by hand) did not deactivate it either.
# The script then calls dbo.sp_MSsubscription_cleanup in the distribution database, the
# procedure these jobs use (KB4014798), with a cutoff of one hour: the subscription becomes
# inactive (status 0). The agent started again fails: the subscription must be reinitialized.
# The retention set back to 72, then sp_reinitsubscription and a new snapshot.
# Needs 00-setup.sh first. Run it before recording, and keep its output: the recording shows it.
# Usage: ./demos/module_08/04-expiration.sh     (with Podman: ENGINE=podman ./demos/module_08/04-expiration.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=rpllab1-m08_Journal-m08_pubJournal-RPLLAB3-2
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
running() {  # 1 when the Distribution Agent job of m08_pubJournal is running
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);" | tr -d '[:space:]'
}
subscription() {  # the subscription of m08_Journal as the distribution database keeps it
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT s.subscriber_db, s.status, s.subscription_time,
               (SELECT COUNT(*) FROM dbo.MSrepl_commands c WHERE c.publisher_database_id = s.publisher_database_id) AS commands_kept
        FROM dbo.MSsubscriptions s WHERE s.subscriber_db = N'm08_Journal' AND s.article_id > 0;"
}

echo "== rpllab2: the retention of the distribution database, and the job that applies it"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT name, min_distretention, max_distretention, history_retention FROM msdb.dbo.MSdistributiondbs;
    SELECT LEFT(js.command, 100) AS command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
    WHERE j.name = N'Distribution clean up: distribution';"
echo "== rpllab1: the retention of the publication (hours), another setting"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON; SELECT name, retention FROM dbo.syspublications;"

echo
echo "== rpllab2: max_distretention set to 1 hour"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.sp_changedistributiondb @database = N'distribution', @property = N'max_distretention', @value = N'1';
    SELECT LEFT(js.command, 100) AS command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
    WHERE j.name = N'Distribution clean up: distribution';"
echo "== rpllab2: the Distribution Agent of m08_pubJournal disabled and stopped"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 0;"
[ "$(running)" = 1 ] && sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
    WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
      AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" 0 60
w=$(now)
echo "== rpllab1: 100 rows in m08_Journal.dbo.Event at $w"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON; INSERT dbo.Event (Body) SELECT TOP (100) 'expiration' FROM sys.all_objects;
    SELECT COUNT(*) AS rows_on_rpllab1 FROM dbo.Event;"
wait_for rpllab2 "SELECT IIF(MAX(entry_time) >= '$w', 1, 0) FROM distribution.dbo.MSrepl_transactions" 1 60
subscription

echo
echo "== rpllab2: the commands of $w older than max_distretention (1 hour): about 61 minutes"
until [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT IIF(DATEDIFF(minute, '$w', GETDATE()) > 60, 1, 0);" | tr -d '[:space:]')" = 1 ]; do
    sleep 60
done
echo "$(now) the subscription, after 6 runs of the cleanup job"
subscription
echo "-- the job \"Expired subscription clean up\", daily, started by hand"
n0=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'Expired subscription clean up' AND h.step_id = 0;" | tr -d '[:space:]')
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'Expired subscription clean up';"
wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'Expired subscription clean up' AND h.step_id = 0" $((n0 + 1)) 120
subscription
echo "-- dbo.sp_MSsubscription_cleanup, the procedure of the cleanup, with a cutoff of one hour"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; DECLARE @c datetime = DATEADD(hour, -1, GETDATE());
    EXEC dbo.sp_MSsubscription_cleanup @cutoff_time = @c;"
d=$(now)
subscription
echo "-- the last runs of the cleanup job"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT TOP (2) msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run, h.run_status, LEFT(h.message, 200) AS message
    FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'Distribution clean up: distribution' AND h.step_id = 1 ORDER BY h.instance_id DESC;"

echo
echo "== rpllab2: the Distribution Agent enabled and started"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 1; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'm08_Journal' AND h.time >= '$d' AND h.runstatus = 6" 1 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (3) h.time, h.runstatus, LEFT(h.comments, 160) AS comments FROM dbo.MSdistribution_history h
    JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id WHERE a.subscriber_db = N'm08_Journal' ORDER BY h.time DESC, h.timestamp DESC;
    SELECT time, error_code, LEFT(error_text, 160) AS error_text FROM dbo.MSrepl_errors WHERE time >= '$d' ORDER BY time, id;"

echo
echo "== rpllab2: max_distretention set back to 72"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.sp_changedistributiondb @database = N'distribution', @property = N'max_distretention', @value = N'72';"
subscription
echo "== rpllab1: the subscription reinitialized, a new snapshot"
r=$(now)
for i in 1 2 3 4 5; do  # 18752 when the Log Reader Agent is connected (twice on 11 November 2026): called again
    out=$(sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON; EXEC sys.sp_reinitsubscription @publication = N'm08_pubJournal',
              @subscriber = N'rpllab3', @destination_db = N'm08_Journal';" 2>&1) && break
    echo "$out" | grep -q 'Msg 18752' || { echo "$out" >&2; exit 1; }
    echo "(18752, the Log Reader Agent connected: called again)"
    sleep 3
done
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON; EXEC sys.sp_startpublication_snapshot @publication = N'm08_pubJournal';"
[ "$(running)" = 1 ] || sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m08_Journal.dbo.Event" | tr -d '[:space:]')
wait_for rpllab3 "SELECT COUNT(*) FROM m08_Journal.dbo.Event" "$want" 300
subscription
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (2) h.time, h.runstatus, LEFT(h.comments, 120) AS comments FROM dbo.MSdistribution_history h
    JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id WHERE a.subscriber_db = N'm08_Journal' AND h.time >= '$r'
      AND h.comments LIKE N'Delivered snapshot%' ORDER BY h.time DESC;"
echo "rpllab3: $want rows in m08_Journal.dbo.Event, as on rpllab1"
