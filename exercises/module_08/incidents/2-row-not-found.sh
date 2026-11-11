#!/usr/bin/env bash
# Exercise of module 8, incident 2. Played only once incident 1 is repaired: the Log Reader Agent
# of PachadataTraining enabled and running, the category X1 on ex_catalog, nothing pending. Then
# session 2000 is deleted on ex_catalog, as by an application that writes on the subscriber,
# and its price is raised by 1 on rpllab1.
# Usage: ./exercises/module_08/incidents/2-row-not-found.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
job=$(logreader_job)
ok=1
[ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT enabled FROM msdb.dbo.sysjobs WHERE name = N'$job';" | tr -d '[:space:]')" = 1 ] \
    && [ "$(job_running "$job")" = 1 ] || { echo "Incident 1 is not repaired: the Log Reader Agent of PachadataTraining is not enabled and running."; ok=0; }
[ "$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM $subdb.Course.Category WHERE CategoryCode = 'X1';" | tr -d '[:space:]')" = 1 ] \
    || { echo "Incident 1 is not repaired: the category X1 is not on $subdb."; ok=0; }
[ "$(pending)" = 0 ] || { echo "Incident 1 is not repaired: commands are still pending for $subdb."; ok=0; }
[ $ok = 1 ] || exit 1
played 2
sql rpllab3 -d $subdb -Q "SET NOCOUNT ON; DELETE Course.Session WHERE SessionId = 2000;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Session SET Price = Price + 1 WHERE SessionId = 2000;"
echo "Incident 2 played: the price of session 2000 changed on rpllab1. Watch $subdb, find the error and repair"
echo "without reinitializing and without skipping it, then: ./exercises/module_08/incidents/3-duplicate.sh"
