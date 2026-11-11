#!/usr/bin/env bash
# Module 8, clip 8.4. Reinitialize, and what it takes. First pubCatalog, after clips 8.2 and 8.3:
# sp_reinitsubscription marks the subscription; the publication having @immediate_sync =
# false, the Distribution Agent waits for a snapshot ("not yet available") until
# sp_startpublication_snapshot generates one; once it is delivered, the rows of rpllab3 are
# those of rpllab1 again (diff of the checksums, validation with @rowcount_only = 2). Then the
# cost, on Enrollment.Enrollment (151 236 rows): publication m08_pubEnrollment, created with
# @immediate_sync = true so that its snapshot is kept, pushed to m08_Enrollment on rpllab3.
# Reinitialized without a new snapshot (the kept one applied again), then with
# @invalidate_snapshot = 1 and a new snapshot. During each, twice a second, a count of the rows
# on rpllab3 and a one-row update rolled back on rpllab1, timed: what the subscriber shows while
# the snapshot is delivered, and how long the snapshot blocks a writer of the publisher.
# Needs 00-setup.sh first (and 02-errors.sh for the differences that the reinitialization repairs).
# Usage: ./demos/module_08/05-reinit.sh     (with Podman: ENGINE=podman ./demos/module_08/05-reinit.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
agent_of() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSdistribution_agents WHERE publication = N'$1' AND subscriber_db <> N'virtual';" | tr -d '[:space:]'; }
rows() {
    local db=$([ $1 = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $1 -d $db -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT($3, ' ', BINARY_CHECKSUM(*)) FROM $2 ORDER BY $3;" | tr -d '\r' | sed '/^$/d'
}
probe() {  # seconds: the subscriber's count and the publisher's update time, twice a second (UTC, the clock of the containers)
    local end=$(( $(date +%s) + $1 )) s p
    while [ "$(date +%s)" -lt $end ]; do
        s=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SET LOCK_TIMEOUT 1000;
            SELECT COUNT(*) FROM m08_Enrollment.Enrollment.Enrollment;" 2>&1 | tr -d '\r' | sed '/^$/d' | head -1 | cut -c1-40)
        p=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SET LOCK_TIMEOUT 10000; DECLARE @t datetime2 = SYSDATETIME();
            BEGIN TRAN; UPDATE PachadataTraining.Enrollment.Enrollment SET Discount = Discount WHERE EnrollmentId = 1; ROLLBACK;
            SELECT DATEDIFF(millisecond, @t, SYSDATETIME());" 2>&1 | tr -d '\r' | sed '/^$/d' | head -1 | cut -c1-40)
        echo "$(date -u +%T.%N | cut -c1-12) $s $p"
        sleep 0.3
    done
}
summary() {  # the probe lines: the readings of the subscriber that are not 151236, and the longest update
    awk '{ n++; if ($2 != 151236) { print "  " $1 " rpllab3 counted " $2 " rows" }
           if ($3 + 0 > max) { max = $3 + 0; at = $1 } }
         END { printf "  %d readings; longest update on rpllab1: %d ms (%s)\n", n, max, at }'
}
history() {  # the snapshot and distribution lines of a publication since a time
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT TOP (1) N'snapshot' AS agent, MIN(h.time) OVER () AS first_line, h.time AS last_line, LEFT(h.comments, 70) AS comments
        FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
        WHERE a.publication = N'$1' AND h.time >= '$2' ORDER BY h.time DESC;
        SELECT h.time, LEFT(h.comments, 130) AS comments FROM dbo.MSdistribution_history h
        WHERE h.agent_id = $(agent_of $1) AND h.time >= '$2' AND (h.comments LIKE N'Delivered snapshot%' OR h.comments LIKE N'%not yet available%')
        ORDER BY h.time;"
}

reinit() {  # publication, subscription database, more parameters: sp_reinitsubscription, tried again on 18752
    # Measured on 11 November 2026: one call in six refused with 18752 (sp_repldone, called by the
    # procedure, while the Log Reader Agent of PachadataTraining is connected); the next call passes.
    local i out
    for i in 1 2 3 4 5; do
        out=$(sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_reinitsubscription @publication = N'$1', @subscriber = N'rpllab3',
                  @destination_db = N'$2'${3:+, $3};" 2>&1) && { [ -n "$out" ] && echo "$out"; return 0; }
        echo "$out" | grep -q 'Msg 18752' || { echo "$out" >&2; return 1; }
        echo "(18752, the Log Reader Agent connected: called again)"
        sleep 2
    done
    return 1
}

cat_agent=$(agent_of pubCatalog)
echo "== rpllab1: pubCatalog, the subscription of rpllab3 reinitialized"
m=$(now)
reinit pubCatalog PachaCatalog
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; SELECT name, immediate_sync FROM dbo.syspublications WHERE name = N'pubCatalog';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $cat_agent AND time >= '$m' AND comments LIKE N'%not yet available%'" 1 120
history pubCatalog "$m"
echo "-- a new snapshot"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $cat_agent AND time >= '$m' AND comments LIKE N'Delivered snapshot%'" 1 180
history pubCatalog "$m"
echo "-- the checksums of each row: < rpllab1, > rpllab3"
for t in "Course.Category CategoryCode" "Course.Session SessionId"; do
    set -- $t
    diff <(rows rpllab1 $1 $2) <(rows rpllab3 $1 $2) && echo "$1: same rows on both sides"
done
v=$(now)
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_publication_validation @publication = N'pubCatalog', @rowcount_only = 2;" > /dev/null
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $cat_agent AND time >= '$v' AND comments LIKE N'Table %'" 3 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; SELECT LEFT(comments, 100) AS validation FROM dbo.MSdistribution_history
    WHERE agent_id = $cat_agent AND time >= '$v' AND comments LIKE N'Table %' ORDER BY time, timestamp;"

echo
echo "== rpllab1: m08_pubEnrollment, Enrollment.Enrollment pushed to m08_Enrollment on rpllab3"
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m08_Enrollment;"
sql rpllab3 -d m08_Enrollment -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Enrollment');"
m=$(now); s=$(date +%s)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'm08_pubEnrollment', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'true';
    EXEC sys.sp_addpublication_snapshot @publication = N'm08_pubEnrollment', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm08_pubEnrollment', @article = N'Enrollment', @source_owner = N'Enrollment', @source_object = N'Enrollment';
    EXEC sys.sp_addsubscription @publication = N'm08_pubEnrollment', @subscriber = N'rpllab3',
         @destination_db = N'm08_Enrollment', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm08_pubEnrollment', @subscriber = N'rpllab3',
         @subscriber_db = N'm08_Enrollment', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
    EXEC sys.sp_startpublication_snapshot @publication = N'm08_pubEnrollment';" > /dev/null 2>&1
count="SELECT ISNULL((SELECT SUM(rows) FROM m08_Enrollment.sys.partitions WHERE object_id = OBJECT_ID(N'm08_Enrollment.Enrollment.Enrollment') AND index_id < 2), -1)"
wait_for rpllab3 "$count" 151236 300
echo "first initialization: 151236 rows on rpllab3 after $(( $(date +%s) - s )) s"
history m08_pubEnrollment "$m"

echo
echo "== reinitialized without a new snapshot: the kept snapshot applied again"
m=$(now)
reinit m08_pubEnrollment m08_Enrollment
probe 25 | summary
history m08_pubEnrollment "$m"

echo
echo "== reinitialized with @invalidate_snapshot = 1, and a new snapshot"
m=$(now)
reinit m08_pubEnrollment m08_Enrollment "@invalidate_snapshot = 1"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'm08_pubEnrollment';"
probe 40 | summary
history m08_pubEnrollment "$m"
