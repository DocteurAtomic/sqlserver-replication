#!/usr/bin/env bash
# Module 9, clip 9.1. The agent profiles. Where they live: msdb of the distributor (rpllab2),
# not the distribution database and not the publisher. The profiles of the Distribution Agent
# and the default one; the list of the parameters an agent knows (MSagentparameterlist, with
# is_reloadable). A user profile, "m09 Month-end", created by sp_add_agent_profile: it starts
# with the twelve parameters of the default profile; -CommitBatchSize set to 1000 and
# -CommitBatchThreshold to 10000 by sp_change_agent_parameter. The profile given to the
# Distribution Agent of m09_pubBilling by sp_update_agent_profile, called in the distribution
# database. Then the command line of the job step against the profile: -CommitBatchSize 50 and
# an output file added to the command, the agent restarted; its output lists the values it took
# from the profile, and -CommitBatchSize is not among them. The command is set back and the
# agent restarted, on the profile "m09 Month-end"; 02-burst.sh gives it the default profile.
# Needs 00-setup.sh first.
# Usage: ./demos/module_09/01-profiles.sh     (with Podman: ENGINE=podman ./demos/module_09/01-profiles.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_09/lib.sh

echo "== rpllab2: where the profiles are"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT N'msdb' AS db, OBJECT_ID(N'msdb.dbo.MSagent_profiles') AS MSagent_profiles
    UNION ALL SELECT N'distribution', OBJECT_ID(N'distribution.dbo.MSagent_profiles');"
echo "-- rpllab1, the publisher"
sql rpllab1 -Q "SET NOCOUNT ON; SELECT N'msdb' AS db, OBJECT_ID(N'msdb.dbo.MSagent_profiles') AS MSagent_profiles;"

echo
echo "== rpllab2: the profiles of the Distribution Agent (agent_type 3)"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT profile_id, profile_name, type, def_profile FROM msdb.dbo.MSagent_profiles WHERE agent_type = 3 ORDER BY profile_id;"
echo "-- the default profile"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT a.parameter_name, a.value FROM msdb.dbo.MSagent_parameters a JOIN msdb.dbo.MSagent_profiles p ON p.profile_id = a.profile_id
    WHERE p.agent_type = 3 AND p.def_profile = 1 ORDER BY a.parameter_name;"
echo "-- the parameters the agent knows, and those it reloads while running"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT parameter_name, default_value, min_value, max_value, is_reloadable FROM msdb.dbo.MSagentparameterlist
    WHERE agent_type = 3 AND parameter_name IN (N'CommitBatchSize', N'CommitBatchThreshold', N'SubscriptionStreams',
          N'PollingInterval', N'QueryTimeout', N'ProfileReloadInterval', N'SkipErrors') ORDER BY parameter_name;"
echo "-- the profile of each Distribution Agent"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT a.id, a.name, p.profile_name FROM distribution.dbo.MSdistribution_agents a
    JOIN msdb.dbo.MSagent_profiles p ON p.profile_id = a.profile_id ORDER BY a.id;"

echo
echo "== rpllab2: a user profile, m09 Month-end"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @id int;
    EXEC sys.sp_add_agent_profile @profile_id = @id OUTPUT, @profile_name = N'm09 Month-end', @agent_type = 3,
         @profile_type = 1, @description = N'Month-end closing of m09_Billing';
    SELECT @id AS profile_id;
    SELECT COUNT(*) AS parameters_copied FROM msdb.dbo.MSagent_parameters WHERE profile_id = @id;
    EXEC sys.sp_change_agent_parameter @profile_id = @id, @parameter_name = N'-CommitBatchSize', @parameter_value = N'1000';
    EXEC sys.sp_change_agent_parameter @profile_id = @id, @parameter_name = N'-CommitBatchThreshold', @parameter_value = N'10000';"
p=$(profile_id "m09 Month-end")
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; EXEC sys.sp_help_agent_parameter @profile_id = $p;"
echo "-- given to the Distribution Agent of m09_pubBilling"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_update_agent_profile @agent_type = 3, @agent_id = $agent, @profile_id = $p;
    SELECT a.id, a.name, p.profile_name FROM dbo.MSdistribution_agents a
    JOIN msdb.dbo.MSagent_profiles p ON p.profile_id = a.profile_id WHERE a.id = $agent;" | grep -v 'is_reloadable'

echo
echo "== rpllab2: the command line of the job step against the profile"
sql rpllab2 -Q "SET NOCOUNT ON;
    DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                                WHERE j.name = N'$job' AND js.step_id = 2);
    SET @c = @c + N' -CommitBatchSize 50 -Output /var/opt/mssql/log/m09_distrib.log -OutputVerboseLevel 1';
    EXEC msdb.dbo.sp_update_jobstep @job_name = N'$job', @step_id = 2, @command = @c;
    SELECT RIGHT(js.command, 100) AS end_of_command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id WHERE j.name = N'$job' AND js.step_id = 2;"
$engine exec rpllab2 rm -f /var/opt/mssql/log/m09_distrib.log
restart
# The agent writes its output in UTF-16; the two lists come in its first seconds.
for i in $(seq 1 60); do
    $engine exec rpllab2 sh -c 'test -f /var/opt/mssql/log/m09_distrib.log' 2>/dev/null \
        && [ "$(agent_output | grep -c 'Parameter values obtained from agent profile')" -ge 1 ] && break
    sleep 1
done
agent_output | grep -A20 'User-specified agent parameter values' | grep -v -- '-X[A-Z]' | sed -n '1,13p'
agent_output | grep -A14 'Parameter values obtained from agent profile' | sed '/^[0-9]\{4\}-.*OLE DB/,$d'

echo
echo "== rpllab2: the command set back"
sql rpllab2 -Q "SET NOCOUNT ON;
    DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                                WHERE j.name = N'$job' AND js.step_id = 2);
    SET @c = REPLACE(@c, N' -CommitBatchSize 50 -Output /var/opt/mssql/log/m09_distrib.log -OutputVerboseLevel 1', N'');
    EXEC msdb.dbo.sp_update_jobstep @job_name = N'$job', @step_id = 2, @command = @c;
    SELECT RIGHT(js.command, 100) AS end_of_command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id WHERE j.name = N'$job' AND js.step_id = 2;"
restart
$engine exec rpllab2 rm -f /var/opt/mssql/log/m09_distrib.log
