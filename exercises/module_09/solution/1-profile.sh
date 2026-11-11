#!/usr/bin/env bash
# Exercise of module 9, a solution. On rpllab2, a user profile for the Distribution Agent,
# ex_month_end, created by sp_add_agent_profile (it starts with the parameters of the default
# profile); its -CommitBatchSize set to 1000 and its -CommitBatchThreshold to 10000 by
# sp_change_agent_parameter; given to the Distribution Agent of ex_billing by
# sp_update_agent_profile, called in the distribution database; the job of the agent restarted,
# so that it reads its profile again. The command of its job is left as it is.
# Usage: ./exercises/module_09/solution/1-profile.sh     (with Podman: ENGINE=podman ./exercises/module_09/solution/1-profile.sh)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_09/tools/lib.sh
agent=$(dist_agent)
job=$(dist_job)
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @id int;
    EXEC sys.sp_add_agent_profile @profile_id = @id OUTPUT, @profile_name = N'ex_month_end', @agent_type = 3,
         @profile_type = 1, @description = N'Month-end closing of ex_billing';
    EXEC sys.sp_change_agent_parameter @profile_id = @id, @parameter_name = N'-CommitBatchSize', @parameter_value = N'1000';
    EXEC sys.sp_change_agent_parameter @profile_id = @id, @parameter_name = N'-CommitBatchThreshold', @parameter_value = N'10000';
    EXEC sys.sp_update_agent_profile @agent_type = 3, @agent_id = $agent, @profile_id = @id;" > /dev/null
if [ "$(job_running "$job")" = 1 ]; then
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
    wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" 0 60
fi
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
echo "Profile ex_month_end given to the Distribution Agent of ex_billing, agent restarted."
