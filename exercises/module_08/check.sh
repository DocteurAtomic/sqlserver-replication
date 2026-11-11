#!/usr/bin/env bash
# Exercise of module 8: checks that the three incidents were played and repaired, without
# reinitializing and without skipping errors. It reads a state, never a script:
# - the three incidents played (ex_incident.dbo.Played on rpllab1);
# - no snapshot delivered to ex_catalog since incident 1 (a reinitialization would deliver one);
# - the Log Reader Agent of PachadataTraining enabled and running;
# - the Distribution Agent of ex_catalog on a profile that skips no error and without -SkipErrors
#   on the command of its job, running, with no command pending;
# - the categories X1 and X3 and session 2000 on ex_catalog as on rpllab1;
# - sp_publication_validation with @rowcount_only = 2 (row counts and checksums, the three
#   articles of ex_pubCatalog being unfiltered) passed for the three tables.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing. Less than a
# minute.
# Usage: ./exercises/module_08/check.sh     (with Podman: ENGINE=podman ./exercises/module_08/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
rc=0
ok() { echo "OK   $1"; }
ko() { echo "FAIL $1"; rc=1; }
q1() { sql rpllab1 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | sed '/^$/d'; }
q2() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | sed '/^$/d'; }
q3() { sql rpllab3 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | tr -d '\r' | sed '/^$/d'; }

n=$(q1 "SELECT IIF(DB_ID(N'ex_incident') IS NULL, -1, (SELECT COUNT(*) FROM ex_incident.dbo.Played WHERE step IN (1, 2, 3)));")
if [ "$n" = 3 ]; then ok "the three incidents were played"
else ko "the three incidents were played (found: $n; play the next one with exercises/module_08/incidents/)"; echo "check: nothing else is read before the three incidents are played."; exit 1; fi
agent=$(dist_agent)
if [ -z "$agent" ]; then ko "the subscription of ex_catalog to ex_pubCatalog exists"; exit 1; fi
t1=$(q1 "SELECT CONVERT(varchar(23), played_at, 121) FROM ex_incident.dbo.Played WHERE step = 1;")
s=$(q2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$t1' AND comments LIKE N'Delivered snapshot%';")
[ "$s" = 0 ] && ok "no snapshot delivered to ex_catalog since incident 1 (no reinitialization)" \
             || ko "no snapshot delivered to ex_catalog since incident 1 (found $s: the subscription was reinitialized)"

job=$(logreader_job)
e=$(q2 "SELECT enabled FROM msdb.dbo.sysjobs WHERE name = N'$job';")
[ "$e" = 1 ] && [ "$(job_running "$job")" = 1 ] && ok "the Log Reader Agent of PachadataTraining is enabled and running" \
    || ko "the Log Reader Agent of PachadataTraining is enabled and running (enabled: $e, running: $(job_running "$job"))"

skip=$(q2 "SELECT ISNULL(MAX(p.value), N'') FROM distribution.dbo.MSdistribution_agents a
           JOIN msdb.dbo.MSagent_parameters p ON p.profile_id = a.profile_id AND p.parameter_name = N'-SkipErrors' WHERE a.id = $agent;")
cmd=$(q2 "SELECT IIF(js.command LIKE N'%-SkipErrors%', 1, 0) FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
          WHERE j.name = N'$(dist_job)' AND js.step_id = 2;")
[ -z "$skip" ] && [ "$cmd" = 0 ] && ok "the Distribution Agent of ex_catalog skips no error (profile and command of its job)" \
    || ko "the Distribution Agent of ex_catalog skips no error (profile -SkipErrors '$skip', -SkipErrors on the command: $cmd)"

if wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$(dist_job)' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
      AND ISNULL((SELECT SUM(UndelivCmdsInDistDB) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent), 0) = 0, 1, 0)" 1 60 2>/dev/null
then ok "the Distribution Agent of ex_catalog is running, with no command pending"
else ko "the Distribution Agent of ex_catalog is running, with no command pending (running: $(job_running "$(dist_job)"), pending: $(pending))"; fi

for c in X1 X3; do
    a=$(q1 "SELECT ISNULL((SELECT Label FROM PachadataTraining.Course.Category WHERE CategoryCode = '$c'), N'(missing)');")
    b=$(q3 "SELECT ISNULL((SELECT Label FROM ex_catalog.Course.Category WHERE CategoryCode = '$c'), N'(missing)');")
    [ "$a" = "$b" ] && ok "category $c on ex_catalog as on rpllab1 ($b)" || ko "category $c on ex_catalog as on rpllab1 (rpllab1: $a, ex_catalog: $b)"
done
a=$(q1 "SELECT ISNULL(CONVERT(varchar(20), (SELECT Price FROM PachadataTraining.Course.Session WHERE SessionId = 2000)), 'missing');")
b=$(q3 "SELECT ISNULL(CONVERT(varchar(20), (SELECT Price FROM ex_catalog.Course.Session WHERE SessionId = 2000)), 'missing');")
[ "$a" = "$b" ] && ok "session 2000 on ex_catalog as on rpllab1 (price $b)" || ko "session 2000 on ex_catalog as on rpllab1 (rpllab1: $a, ex_catalog: $b)"

if [ $rc -eq 0 ]; then
    m=$(now)
    echo "check: sp_publication_validation @rowcount_only = 2 on ex_pubCatalog at $m"
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_publication_validation @publication = N'$pub', @rowcount_only = 2;" > /dev/null
    if wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'Table %'" 3 120 2>/dev/null; then
        sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'     ', LEFT(comments, 110)) FROM distribution.dbo.MSdistribution_history
            WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'Table %' ORDER BY time, timestamp;" | tr -d '\r' | sed '/^$/d'
        p=$(q2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$m'
                AND comments LIKE N'Table % passed rowcount % and checksum validation.%';")
        [ "$p" = 3 ] && ok "the three tables passed the validation with checksums" || ko "the three tables passed the validation with checksums ($p of 3)"
    else
        ko "the validation reached the history of the Distribution Agent within 2 minutes"
    fi
else
    echo "check: the validation is run once everything above holds."
fi
[ $rc -eq 0 ] && echo "The three incidents are repaired: ex_catalog has the rows of rpllab1, and its agents run."
exit $rc
