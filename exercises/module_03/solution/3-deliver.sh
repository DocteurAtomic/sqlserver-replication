#!/usr/bin/env bash
# Exercise of module 3, solution: the first snapshot, without waiting for the night. Starts the
# Snapshot Agent of ex_pubRef and waits until it has written the snapshot, then starts the
# Distribution Agent of ex_ref and waits until it has applied it. A run of the Distribution Agent
# still going (the one sp_addsubscription started) is stopped first.
# Usage: ./exercises/module_03/solution/3-deliver.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubRef';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
                  WHERE a.publication = N'ex_pubRef' AND h.runstatus = 2 AND h.comments LIKE N'%snapshot of % article(s) was generated%'" 1 180
job=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'ex_ref';" | tr -d '[:space:]')
running="SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
         WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
           AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $running" | tr -d '[:space:]')" != 0 ]; then
    sql rpllab2 -Q "EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
    wait_for rpllab2 "$running" 0 60
fi
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpushsubscription_agent @publication = N'ex_pubRef',
    @subscriber = N'rpllab3', @subscriber_db = N'ex_ref';"
wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.subscriber_db = N'ex_ref' AND h.runstatus = 2 AND h.comments LIKE N'Applied the snapshot%'), 1, 0)" 1 180
echo "Snapshot of ex_pubRef applied to ex_ref."
