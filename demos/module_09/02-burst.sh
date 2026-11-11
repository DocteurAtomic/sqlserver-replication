#!/usr/bin/env bash
# Module 9, clip 9.2. The month-end closing of m09_Billing: 200,000 invoice lines change status
# in 2,000 transactions of 100 lines. First with the Distribution Agent running on the default
# profile: it keeps up. Then the same closing during a maintenance window of the subscriber
# (the job of the agent stopped, 200,000 commands pending), and the catch-up timed from the
# restart, three times: the default profile, "m09 Month-end" (clip 9.1: -CommitBatchSize 1000,
# -CommitBatchThreshold 10000), and "m09 Streams", the default parameters plus
# -SubscriptionStreams 4 (added by sp_add_agent_parameter), with the sessions of the agent on
# rpllab3 counted during the catch-up. Last, the whole closing in one transaction of 200,000
# rows, caught up on the default profile. The agent is left on the default profile.
# Needs 00-setup.sh and 01-profiles.sh first. About five minutes.
# Usage: ./demos/module_09/02-burst.sh     (with Podman: ENGINE=podman ./demos/module_09/02-burst.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_09/lib.sh

use_profile() {  # give a profile to the Distribution Agent of m09_pubBilling (read at the next start)
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        EXEC sys.sp_update_agent_profile @agent_type = 3, @agent_id = $agent, @profile_id = $(profile_id "$1");" | grep -v 'is_reloadable' || true
    echo "-- profile of the agent: $1"
}
closing() {  # the closing, on rpllab1; $1: 2000 (transactions of 100 lines) or 1 (one transaction)
    local cur new s
    cur=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT Status FROM m09_Billing.dbo.InvoiceLine WHERE LineId = 1;" | tr -d '[:space:]')
    new=$([ "$cur" = OPEN ] && echo CLOSED || echo OPEN)
    s=$(date +%s)
    if [ "$1" = 1 ]; then
        sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON; UPDATE dbo.InvoiceLine SET Status = '$new';"
    else
        sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
            DECLARE @i int = 0;
            WHILE @i < 2000
            BEGIN
                UPDATE dbo.InvoiceLine SET Status = '$new' WHERE LineId > @i * 100 AND LineId <= (@i + 1) * 100;
                SET @i += 1;
            END;"
    fi
    echo "rpllab1: closing, 200000 lines set to $new in $1 transaction(s), $(( $(date +%s) - s )) s"
    status=$new
}
follow() {  # pending commands every 5 s until the subscriber has the 200,000 lines; $1: what to count on rpllab3
    local t0 p t n sessions=0 next=0
    t0=$(date +%s)
    printf '%-8s %-8s %s\n' seconds pending sessions_on_rpllab3
    while :; do
        p=$(pending)
        t=$(( $(date +%s) - t0 ))
        n=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name = N'rpllab1_m09_Billing_m09_pubBilling';" | tr -d '[:space:]')
        [ "$n" -gt "$sessions" ] && sessions=$n
        if [ "$t" -ge "$next" ] || [ "$p" = 0 ]; then printf '%-8s %-8s %s\n' "$t" "$p" "$n"; next=$(( t + 5 )); fi
        if [ "$p" = 0 ] && [ "$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m09_Billing.dbo.InvoiceLine WHERE Status = '$status';" | tr -d '[:space:]')" = 200000 ]; then
            echo "rpllab3: the 200000 lines are $status, $t s after the start (at most $sessions session(s) of the agent seen on rpllab3)"
            return
        fi
        [ "$t" -ge 600 ] && { echo "rpllab3: not delivered after 600 s" >&2; return 1; }
        sleep 1
    done
}
window() {  # the agent stopped, the closing, the 200,000 commands written by the Log Reader Agent
    stop_agent
    echo "rpllab2: the Distribution Agent stopped (maintenance window of the subscriber)"
    closing "$1"
    wait_for rpllab2 "SELECT IIF(ISNULL(SUM(UndelivCmdsInDistDB), 0) >= 200000, 1, 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent" 1 300
    echo "rpllab2: $(pending) commands pending, the Distribution Agent started"
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
}

echo "== 1. the closing, Distribution Agent running"
use_profile "Default agent profile"
restart
closing 2000
follow

echo
echo "== 2. the closing in the maintenance window, caught up on the default profile"
window 2000
follow

echo
echo "== 3. the same, on the profile m09 Month-end"
sql rpllab2 -Q "SET NOCOUNT ON; SELECT parameter_name, value FROM msdb.dbo.MSagent_parameters
    WHERE profile_id = $(profile_id "m09 Month-end") AND parameter_name LIKE N'-CommitBatch%';"
use_profile "m09 Month-end"
window 2000
follow

echo
echo "== 4. the same, on a profile with -SubscriptionStreams 4"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @id int;
    EXEC sys.sp_add_agent_profile @profile_id = @id OUTPUT, @profile_name = N'm09 Streams', @agent_type = 3,
         @profile_type = 1, @description = N'Default parameters and four streams';
    EXEC sys.sp_add_agent_parameter @profile_id = @id, @parameter_name = N'-SubscriptionStreams', @parameter_value = N'4';
    SELECT parameter_name, value FROM msdb.dbo.MSagent_parameters WHERE profile_id = @id AND parameter_name IN (N'-SubscriptionStreams', N'-CommitBatchSize', N'-CommitBatchThreshold');" \
    | grep -v 'is_reloadable\|dynamically reloadable'
use_profile "m09 Streams"
window 2000
follow

echo
echo "== 5. the closing in one transaction, caught up on the default profile"
use_profile "Default agent profile"
window 1
follow
