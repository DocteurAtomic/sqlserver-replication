#!/usr/bin/env bash
# Exercise of module 8, incident 3. Played only once incident 2 is repaired: session 2000 on
# ex_catalog with the price of rpllab1 (a skipped error leaves it missing), the Distribution
# Agent running, nothing pending. Then the category X3 is inserted on ex_catalog, then on
# rpllab1 with another label: the insert of rpllab1 meets a duplicate key on ex_catalog.
# Usage: ./exercises/module_08/incidents/3-duplicate.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
ok=1
p1=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT Price FROM PachadataTraining.Course.Session WHERE SessionId = 2000;" | tr -d '[:space:]')
p3=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(CONVERT(varchar(20), (SELECT Price FROM $subdb.Course.Session WHERE SessionId = 2000)), 'missing');" | tr -d '[:space:]')
[ "$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM ex_incident.dbo.Played WHERE step = 2;" | tr -d '[:space:]')" = 1 ] \
    || { echo "Incident 2 has not been played yet: ./exercises/module_08/incidents/2-row-not-found.sh"; exit 1; }
[ "$p1" = "$p3" ] || { echo "Incident 2 is not repaired: session 2000 on $subdb has price $p3, $p1 on rpllab1."; ok=0; }
[ "$(job_running "$(dist_job)")" = 1 ] || { echo "Incident 2 is not repaired: the Distribution Agent of $subdb is not running."; ok=0; }
[ "$(pending)" = 0 ] || { echo "Incident 2 is not repaired: commands are still pending for $subdb."; ok=0; }
[ $ok = 1 ] || exit 1
played 3
sql rpllab3 -d $subdb -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('X3', 'Written on rpllab3', 'Exercise of module 8');"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('X3', 'Incident 3', 'Exercise of module 8');"
echo "Incident 3 played: the category X3 inserted on rpllab1. Watch $subdb, find the error and repair"
echo "without reinitializing and without skipping it, then: ./exercises/module_08/check.sh"
