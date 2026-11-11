#!/usr/bin/env bash
# Exercise of module 7: checks the morning query and the response to the failure of an agent.
# It reads the state of rpllab2, then provokes a failure and reads what the work of the exercise
# made of it, never a script.
# First the state, on rpllab2: the alert "Replication: agent failure" (14151) is enabled; the job
# ex_agent_failure_watch exists, is enabled, runs on this server and every 5 minutes at most;
# ex_monitor.dbo.ReplHealth and ex_monitor.dbo.AgentFailure exist; ReplHealth returns, for the
# subscription of ex_catalog to ex_pubCatalog, an agent running (status 1, 3 or 4) and no pending
# command. If one of these is missing, it says so and stops there, with 1.
# Then the failure: ex_catalog taken offline on rpllab3 and the category X7 inserted on rpllab1.
# ReplHealth must report the agent failed (6) with at least one pending command, and a row for
# ex_catalog must reach ex_monitor.dbo.AgentFailure. On Linux the alert itself never fires (the
# alert engine of SQL Server Agent is disabled): the proof read here is the row the agent writes
# to msdb.dbo.sysreplicationalerts, copied by the job. Last, ex_catalog online again and X7
# deleted, whatever happened before: ReplHealth must report the agent running and nothing
# pending.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing. About three
# minutes on the solution: the job runs once a minute.
# Usage: ./exercises/module_07/check.sh     (with Podman: ENGINE=podman ./exercises/module_07/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
# The subscription of the exercise, as ReplHealth returns it: agent_status:pending_commands.
health="DECLARE @t TABLE (publication sysname NULL, subscriber_db sysname NULL, agent_status int NULL,
                         latency_seconds int NULL, pending_commands int NULL);
        INSERT @t EXEC ex_monitor.dbo.ReplHealth;
        SELECT CONCAT(agent_status, ':', pending_commands) FROM @t
        WHERE publication = N'ex_pubCatalog' AND subscriber_db = N'ex_catalog';"
out=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE message_id = 14151 AND enabled = 1), 1, 0),
    CONCAT(N'the alert Replication: agent failure (14151) is enabled on rpllab2 (found: ',
           ISNULL((SELECT TOP (1) IIF(enabled = 1, N'enabled', N'disabled') FROM msdb.dbo.sysalerts WHERE message_id = 14151),
                  N'no alert, no distributor'), N')');
DECLARE @job uniqueidentifier = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = N'ex_agent_failure_watch');
INSERT @r SELECT IIF(@job IS NOT NULL, 1, 0), N'the job ex_agent_failure_watch exists on rpllab2';
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE job_id = @job AND enabled = 1)
                     AND EXISTS (SELECT * FROM msdb.dbo.sysjobservers WHERE job_id = @job AND server_id = 0), 1, 0),
    N'the job ex_agent_failure_watch is enabled and targets this server (sp_add_jobserver)';
-- freq_subday_type 2 seconds, 4 minutes.
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.sysjobschedules x JOIN msdb.dbo.sysschedules s ON s.schedule_id = x.schedule_id
                             WHERE x.job_id = @job AND s.enabled = 1 AND s.freq_type = 4
                               AND (s.freq_subday_type = 2 OR (s.freq_subday_type = 4 AND s.freq_subday_interval <= 5))), 1, 0),
    N'the job ex_agent_failure_watch has an enabled schedule, every day, every 5 minutes at most';
INSERT @r SELECT IIF(OBJECT_ID(N'ex_monitor.dbo.ReplHealth', N'P') IS NOT NULL, 1, 0), N'the procedure ex_monitor.dbo.ReplHealth exists';
INSERT @r SELECT IIF(OBJECT_ID(N'ex_monitor.dbo.AgentFailure', N'U') IS NOT NULL, 1, 0), N'the table ex_monitor.dbo.AgentFailure exists';
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
echo "$out"
if echo "$out" | grep -q '^FAIL\|^Msg'; then
    echo "check: the work asked for is not there yet; nothing was provoked."
    exit 1
fi
# 1 when ReplHealth reports the subscription with its agent running (1, 3 or 4) and nothing pending.
running="SET NOCOUNT ON; DECLARE @t TABLE (publication sysname NULL, subscriber_db sysname NULL, agent_status int NULL,
                         latency_seconds int NULL, pending_commands int NULL);
        INSERT @t EXEC ex_monitor.dbo.ReplHealth;
        SELECT COUNT(*) FROM @t WHERE publication = N'ex_pubCatalog' AND subscriber_db = N'ex_catalog'
          AND agent_status IN (1, 3, 4) AND pending_commands = 0;"
if ! wait_for rpllab2 "$running" 1 60 2>/dev/null; then
    echo "FAIL ReplHealth reports the agent of ex_catalog running with no pending command (found agent_status:pending_commands '$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $health" 2>&1 | tr -d '[:space:]')')"
    exit 1
fi
echo "OK   ReplHealth reports the agent of ex_catalog running with no pending command"

restore() {
    sql rpllab3 -Q "SET NOCOUNT ON; IF DATABASEPROPERTYEX(N'ex_catalog', N'Status') = N'OFFLINE' ALTER DATABASE ex_catalog SET ONLINE;" > /dev/null 2>&1
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; DELETE Course.Category WHERE CategoryCode = 'X7';" > /dev/null 2>&1
}
trap restore EXIT
t0=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d')
echo "check: ex_catalog taken offline on rpllab3 and category X7 inserted on rpllab1 at $t0"
sql rpllab3 -Q "SET NOCOUNT ON; ALTER DATABASE ex_catalog SET OFFLINE WITH ROLLBACK IMMEDIATE;" > /dev/null
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('X7', 'Check of module 7', 'Written and deleted by check.sh');" > /dev/null
rc=0
failed="SET NOCOUNT ON; DECLARE @t TABLE (publication sysname NULL, subscriber_db sysname NULL, agent_status int NULL,
                         latency_seconds int NULL, pending_commands int NULL);
        INSERT @t EXEC ex_monitor.dbo.ReplHealth;
        SELECT COUNT(*) FROM @t WHERE publication = N'ex_pubCatalog' AND subscriber_db = N'ex_catalog'
          AND agent_status = 6 AND pending_commands >= 1;"
if wait_for rpllab2 "$failed" 1 150 2>/dev/null; then
    echo "OK   ReplHealth reports the agent of ex_catalog failed (6) with pending commands"
else
    echo "FAIL ReplHealth reports the agent of ex_catalog failed (6) with pending commands (found: $(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $health" 2>&1 | tr -d '[:space:]'))"
    rc=1
fi
if wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM ex_monitor.dbo.AgentFailure WHERE subscriber_db = N'ex_catalog' AND time >= '$t0'" 1 180 2>/dev/null; then
    echo "OK   the failure of the agent of ex_catalog reached ex_monitor.dbo.AgentFailure"
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONCAT(N'     ', CONVERT(varchar(23), time, 121), N' ', LEFT(error_text, 120))
        FROM ex_monitor.dbo.AgentFailure WHERE subscriber_db = N'ex_catalog' AND time >= '$t0' ORDER BY time;"
else
    echo "FAIL the failure of the agent of ex_catalog reached ex_monitor.dbo.AgentFailure within 3 minutes"
    rc=1
fi
echo "check: ex_catalog online again and category X7 deleted"
restore
trap - EXIT
if wait_for rpllab2 "$running" 1 180 2>/dev/null; then
    echo "OK   ReplHealth reports the agent of ex_catalog running again with no pending command"
else
    echo "FAIL ReplHealth reports the agent of ex_catalog running again with no pending command (found: $(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $health" 2>&1 | tr -d '[:space:]'))"
    rc=1
fi
if [ $rc -eq 0 ]; then
    echo "The morning query sees the subscription of ex_catalog, and the failure of its agent reached ex_monitor.dbo.AgentFailure."
fi
exit $rc
