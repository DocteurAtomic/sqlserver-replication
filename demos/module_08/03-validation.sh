#!/usr/bin/env bash
# Module 8, clip 8.3. Validate and compare, after clip 8.2: on rpllab3, session 1001 is missing
# and category Z8 has another label, with the same number of categories. sp_publication_validation
# on rpllab1, with @rowcount_only = 1 (the default, row counts only), then 2 (row counts and
# binary checksums): the Distribution Agent runs the check at the subscriber and writes the
# result in MSdistribution_history (one line per article) and each failure in MSrepl_errors
# (20574), a few seconds later. The alert 20574 and the job "Reinitialize subscriptions having
# data validation failures", which nothing links by default. Last, what replaces tablediff
# (absent on Linux): one checksum per row on each side, compared by diff, which names the rows.
# Needs 00-setup.sh and 02-errors.sh first.
# Usage: ./demos/module_08/03-validation.sh     (with Podman: ENGINE=podman ./demos/module_08/03-validation.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1
agent=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSdistribution_agents WHERE name = N'$job';" | tr -d '[:space:]')
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
validate() {  # @rowcount_only: runs the validation, waits for its three lines, prints them and the errors
    local m s
    m=$(now)
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_publication_validation @publication = N'pubCatalog', @rowcount_only = $1;"
    s=$(date +%s)
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'Table %'" 3 120
    echo "-- MSdistribution_history, $(( $(date +%s) - s )) s after the call"
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT time, error_id, comments FROM dbo.MSdistribution_history
        WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'Table %' ORDER BY time, timestamp;"
    echo "-- MSrepl_errors"
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT id, error_code, LEFT(error_text, 120) AS error_text FROM dbo.MSrepl_errors WHERE time >= '$m' ORDER BY id;"
}
rows() {  # the key and a checksum of each row of a table, on one instance
    local db=$([ $1 = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $1 -d $db -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT($3, ' ', BINARY_CHECKSUM(*)) FROM $2 ORDER BY $3;" | tr -d '\r' | sed '/^$/d'
}

echo "== rpllab1 and rpllab3: the number of rows on each side"
for n in rpllab1 rpllab3; do
    db=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $n -d $db -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$n: ', (SELECT COUNT(*) FROM Course.Category), N' categories, ',
        (SELECT COUNT(*) FROM Course.Course), N' courses, ', (SELECT COUNT(*) FROM Course.Session), N' sessions');"
done

echo
echo "== rpllab1: sp_publication_validation, @rowcount_only = 1 (the default)"
validate 1
echo
echo "== rpllab1: sp_publication_validation, @rowcount_only = 2"
validate 2

echo
echo "== rpllab2: the alert of a failed validation, and the job that would reinitialize"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT a.name, a.message_id, a.enabled, ISNULL(j.name, N'(none)') AS job_of_the_alert FROM msdb.dbo.sysalerts a
    LEFT JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id WHERE a.message_id IN (20574, 20575);
    SELECT j.name, j.enabled, (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules x WHERE x.job_id = j.job_id) AS schedules,
           LEFT(js.command, 70) AS command
    FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps js ON js.job_id = j.job_id
    WHERE j.name = N'Reinitialize subscriptions having data validation failures';"

echo
echo "== what replaces tablediff: one checksum per row on each side, compared"
for t in "Course.Category CategoryCode" "Course.Session SessionId"; do
    set -- $t
    echo "-- $1 (key, BINARY_CHECKSUM(*)): < rpllab1, > rpllab3"
    diff <(rows rpllab1 $1 $2) <(rows rpllab3 $1 $2) || true
done
