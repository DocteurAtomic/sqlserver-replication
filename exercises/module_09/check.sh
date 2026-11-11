#!/usr/bin/env bash
# Exercise of module 9: checks that the Distribution Agent of ex_billing applies the month-end
# closing with a profile made for it. It reads a state, never a script:
# - the Distribution Agent of ex_billing on a user profile (type 1, not one of the profiles SQL
#   Server installs) with at least one of the settings measured on the lab to bring the closing
#   from more than 70 seconds to less than 25: -CommitBatchSize 1000 or more,
#   -CommitBatchThreshold 10000 or more, -SubscriptionStreams 2 or more;
# - none of these two parameters, nor -SubscriptionStreams, on the command of its job (the
#   command line wins over the profile);
# - its job running;
# then it plays the closing (tools/month-end.sh): the 200,000 lines must reach ex_billing on
# rpllab3, with no command left pending. The pending commands 20 seconds after the closing are
# printed, and not judged: they depend on the machine.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing. Under a minute
# on the lab, the closing included.
# Usage: ./exercises/module_09/check.sh     (with Podman: ENGINE=podman ./exercises/module_09/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. exercises/module_09/tools/lib.sh
rc=0
ok() { echo "OK   $1"; }
ko() { echo "FAIL $1"; rc=1; }
q2() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | sed '/^$/d'; }

agent=$(dist_agent)
if [ -z "$agent" ]; then ko "the subscription of ex_billing to ex_pubBilling exists (run ./exercises/module_09/1-start.sh)"; exit 1; fi
job=$(dist_job)
prof=$(q2 "SELECT CONCAT(p.profile_name, N'|', p.type) FROM distribution.dbo.MSdistribution_agents a
           JOIN msdb.dbo.MSagent_profiles p ON p.profile_id = a.profile_id WHERE a.id = $agent;")
name=${prof%|*}; type=${prof##*|}
[ "$type" = 1 ] && ok "the Distribution Agent of ex_billing has a user profile ($name)" \
    || ko "the Distribution Agent of ex_billing has a user profile (it has '$name', a profile SQL Server installs)"
param() {  # a parameter of the profile of the agent, 0 when it is missing
    q2 "SELECT ISNULL(MAX(TRY_CONVERT(int, v.value)), 0) FROM distribution.dbo.MSdistribution_agents a
        JOIN msdb.dbo.MSagent_parameters v ON v.profile_id = a.profile_id AND v.parameter_name = N'$1' WHERE a.id = $agent;"
}
cbs=$(param -CommitBatchSize); cbt=$(param -CommitBatchThreshold); str=$(param -SubscriptionStreams)
if [ "$cbs" -ge 1000 ] 2>/dev/null || [ "$cbt" -ge 10000 ] 2>/dev/null || [ "$str" -ge 2 ] 2>/dev/null; then
    ok "the profile is set for the burst (-CommitBatchSize $cbs, -CommitBatchThreshold $cbt, -SubscriptionStreams $str)"
else
    ko "the profile is set for the burst: -CommitBatchSize 1000 or more, or -CommitBatchThreshold 10000 or more, or -SubscriptionStreams 2 or more (found: $cbs, $cbt, $str)"
fi
over=$(q2 "SELECT CONCAT(IIF(js.command LIKE N'%-CommitBatchSize%', N' -CommitBatchSize', N''),
                         IIF(js.command LIKE N'%-CommitBatchThreshold%', N' -CommitBatchThreshold', N''),
                         IIF(js.command LIKE N'%-SubscriptionStreams%', N' -SubscriptionStreams', N''))
           FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id WHERE j.name = N'$job' AND js.step_id = 2;")
[ -z "$over" ] && ok "the command of the job of the agent does not override the profile" \
    || ko "the command of the job of the agent does not override the profile (found:$over)"
if wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" 1 30 2>/dev/null
then ok "the Distribution Agent of ex_billing is running"
else ko "the Distribution Agent of ex_billing is running"; fi

if [ $rc -eq 0 ]; then
    echo "check: month-end closing played"
    if MONTH_END_TIMEOUT=300 ./exercises/module_09/tools/month-end.sh | sed 's/^/     /'; then
        ok "the closing reached ex_billing on rpllab3, nothing pending"
    else
        ko "the closing reached ex_billing on rpllab3 within 5 minutes, nothing pending"
    fi
else
    echo "check: the closing is played once everything above holds."
fi
[ $rc -eq 0 ] && echo "The Distribution Agent of ex_billing applies the month-end closing with its own profile."
exit $rc
