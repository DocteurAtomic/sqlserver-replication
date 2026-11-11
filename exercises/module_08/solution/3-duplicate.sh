#!/usr/bin/env bash
# Exercise of module 8, solution, incident 3. Plays the incident, then: the Distribution Agent
# fails on a duplicate key (2601: the subscriber has a unique clustered index, not a primary key
# constraint). The row of ex_catalog was written there by hand; the publisher is the reference:
# it is deleted on ex_catalog, and the insert of rpllab1 is delivered at the next retry. The job
# is started again if the agent stopped after the delivery.
# Usage: ./exercises/module_08/solution/3-duplicate.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
m=$(now)
./exercises/module_08/incidents/3-duplicate.sh
agent=$(dist_agent)
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSrepl_errors WHERE time >= '$m' AND error_code IN ('2601', '2627')" 1 240
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; SELECT error_code, LEFT(error_text, 120) AS error_text FROM dbo.MSrepl_errors
    WHERE time >= '$m' AND error_code IN ('2601', '2627');"
r=$(now)
sql rpllab3 -d $subdb -Q "SET NOCOUNT ON; DELETE Course.Category WHERE CategoryCode = 'X3';"
wait_for rpllab3 "SELECT ISNULL((SELECT Label FROM $subdb.Course.Category WHERE CategoryCode = 'X3'), N'missing')" "Incident3" 240
job=$(dist_job)
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$r' AND runstatus = 2" 1 10 2>/dev/null || true
if [ "$(job_running "$job")" != 1 ]; then
    echo "The Distribution Agent stopped after the delivery: its job is started again."
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
fi
wait_for rpllab2 "SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent" 0 120
echo "Incident 3 repaired: X3 on $subdb as on rpllab1."
