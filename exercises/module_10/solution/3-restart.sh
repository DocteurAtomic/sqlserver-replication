#!/usr/bin/env bash
# Exercise of module 10, solution: the subscription of ex_catalog gets its login and password
# (sp_changesubscription, one property per call, run at the publisher), then the jobs of the
# Log Reader Agent and of the Distribution Agent are stopped and started on rpllab2, so that
# they connect with their new logins, and the Snapshot Agent is run once to see it work.
# Usage: ./exercises/module_10/solution/3-restart.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changesubscription @publication = N'ex_pubCatalog', @article = N'all', @subscriber = N'rpllab3',
         @destination_db = N'ex_catalog', @property = N'subscriber_login', @value = N'ex_distrib';
    EXEC sys.sp_changesubscription @publication = N'ex_pubCatalog', @article = N'all', @subscriber = N'rpllab3',
         @destination_db = N'ex_catalog', @property = N'subscriber_password', @value = N'Distrib-2026!ex';" > /dev/null
job() {  # the job of an agent, read in the distribution database
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT j.name FROM msdb.dbo.sysjobs j JOIN distribution.dbo.$1 a ON CAST(a.job_id AS uniqueidentifier) = j.job_id WHERE $2;" | sed -n 1p | tr -d '\r' | sed 's/[[:space:]]*$//'
}
running() {
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
restart() {
    if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(running "$1")" | tr -d '[:space:]')" = 1 ]; then
        sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$1';" > /dev/null
        wait_for rpllab2 "$(running "$1")" 0 60
    fi
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$1';" > /dev/null
}
lr=$(job MSlogreader_agents "a.publisher_db = N'PachadataTraining'")
da=$(job MSdistribution_agents "a.subscriber_db = N'ex_catalog'")
sn=$(job MSsnapshot_agents "a.publication = N'ex_pubCatalog'")
restart "$lr"
restart "$da"
wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%-PachadataTraining-%' AND login_name = N'ex_logreader'" 1 90
wait_for rpllab3 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM sys.dm_exec_sessions WHERE login_name = N'ex_distrib'" 1 90
t=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(char(23), SYSDATETIME(), 121);" | sed -n 1p)
restart "$sn"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
                  WHERE a.publication = N'ex_pubCatalog' AND h.time >= '$t' AND h.runstatus IN (2, 6)" 1 90
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.runstatus, LEFT(h.comments, 120) AS comments FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
    WHERE a.publication = N'ex_pubCatalog' ORDER BY h.time DESC, h.timestamp DESC;"
echo "Log Reader Agent connected as ex_logreader, Distribution Agent as ex_distrib."
