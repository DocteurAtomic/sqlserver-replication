#!/usr/bin/env bash
# Exercise of module 9: the month-end closing of ex_billing, played during the maintenance window
# of the subscriber. The job of the Distribution Agent of ex_billing is stopped (the window
# opens); on rpllab1, the 200,000 invoice lines change status in 2,000 transactions of 100 lines
# (OPEN to CLOSED, or back); the script waits until the Log Reader Agent has written the 200,000
# commands to the distribution database, then starts the job again (the window closes). Every
# second, it reads the commands of ex_billing not yet delivered, until there is none left and the
# subscriber has the 200,000 lines in their new status. It prints the pending commands
# 20 seconds after the restart, and the time the catch-up took. Run it with the default
# profile, then with yours.
# Usage: ./exercises/module_09/tools/month-end.sh     (with Podman: ENGINE=podman ./exercises/module_09/tools/month-end.sh)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_09/tools/lib.sh
timeout=${MONTH_END_TIMEOUT:-600}
job=$(dist_job)
active="SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
if [ "$(job_running "$job")" = 1 ]; then
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
    wait_for rpllab2 "$active" 0 60
fi
echo "rpllab2: the Distribution Agent of ex_billing stopped (maintenance window of the subscriber)"
cur=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT Status FROM ex_billing.dbo.InvoiceLine WHERE LineId = 1;" | tr -d '[:space:]')
new=$([ "$cur" = OPEN ] && echo CLOSED || echo OPEN)
s=$(date +%s)
sql rpllab1 -d ex_billing -Q "SET NOCOUNT ON;
    DECLARE @i int = 0;
    WHILE @i < 2000
    BEGIN
        UPDATE dbo.InvoiceLine SET Status = '$new' WHERE LineId > @i * 100 AND LineId <= (@i + 1) * 100;
        SET @i += 1;
    END;"
echo "rpllab1: month-end closing, 200000 invoice lines set to $new in 2000 transactions, $(( $(date +%s) - s )) s"
wait_for rpllab2 "SELECT IIF(ISNULL(SUM(UndelivCmdsInDistDB), 0) >= 200000, 1, 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $(dist_agent)" 1 300
echo "rpllab2: $(pending) commands pending; the Distribution Agent started again"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
e=$(date +%s); at20=""
for i in $(seq 1 "$timeout"); do
    p=$(pending)
    t=$(( $(date +%s) - e ))
    [ -z "$at20" ] && [ "$t" -ge 20 ] && at20=$p && echo "rpllab2: $p commands pending 20 s after the restart"
    if [ "$p" = 0 ] && [ "$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM ex_billing.dbo.InvoiceLine WHERE Status = '$new';" | tr -d '[:space:]')" = 200000 ]; then
        [ -z "$at20" ] && echo "rpllab2: 0 commands pending 20 s after the restart"
        echo "rpllab3: the 200000 lines are $new, $t s after the restart"
        exit 0
    fi
    sleep 1
done
echo "rpllab3: the closing is not delivered ${timeout} s after the restart ($(pending) commands pending)" >&2
exit 1
