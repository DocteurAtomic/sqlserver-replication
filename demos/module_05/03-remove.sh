#!/usr/bin/env bash
# Module 5, clip 5.3. Two subscriptions the reporting server no longer needs, removed, and what
# each removal leaves. The pull subscription of PachaReporting: sp_droppullsubscription on the
# subscriber drops its agent and its registration, but the publisher still knows the
# subscription until sp_dropsubscription. The push subscription of m05_Snapshot (the comparison
# of clip 5.2): sp_dropsubscription on the publisher drops its agent on the distributor and
# leaves the replication objects in the subscription database, which sp_subscription_cleanup
# removes. In both databases the tables and their rows stay. Last, the subscription that remains,
# m05_Enrollment, still receives a tracer token.
# Needs 02-backup.sh first.
# Usage: ./demos/module_05/03-remove.sh     (with Podman: ENGINE=podman ./demos/module_05/03-remove.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
subscriber_side() {  # database: replication objects, tables and rows, distribution jobs of rpllab3
    sql rpllab3 -d $1 -Q "SET NOCOUNT ON;
        SELECT N'$1' AS database_name, type_desc, COUNT(*) AS objects, STRING_AGG(CAST(name AS nvarchar(max)), N', ') AS names
        FROM sys.objects WHERE name LIKE N'MS%' OR name LIKE N'sp_MS%' GROUP BY type_desc;
        SELECT SCHEMA_NAME(t.schema_id) + N'.' + t.name AS table_name, SUM(p.rows) AS rows
        FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id < 2
        WHERE t.name NOT LIKE N'MS%' GROUP BY t.schema_id, t.name ORDER BY 1;
        SELECT COUNT(*) AS distribution_jobs_on_rpllab3 FROM msdb.dbo.sysjobs j
        JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
        WHERE c.name = N'REPL-Distribution' AND j.name LIKE N'%-$1-%';"
}
publisher_side() {  # the subscriptions the publisher knows, one row per subscription
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
        SELECT DISTINCT p.name AS publication, s.dest_db AS subscriber_db,
               IIF(s.subscription_type = 0, N'push', N'pull') AS type, s.status
        FROM dbo.syssubscriptions s JOIN dbo.sysarticles a ON a.artid = s.artid
        JOIN dbo.syspublications p ON p.pubid = a.pubid
        WHERE s.srvid >= 0 ORDER BY 1, 2;"
}

echo "== Before: the subscriptions of the publisher"
publisher_side
echo "-- rpllab3, PachaReporting"
subscriber_side PachaReporting

echo
echo "== rpllab3: the pull subscription dropped at the subscriber"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_droppullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining', @publication = N'pubCatalog';" 2>&1 | filter
subscriber_side PachaReporting
echo "-- rpllab1: the publisher still knows it"
publisher_side
echo "-- rpllab1: sp_dropsubscription"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3',
         @destination_db = N'PachaReporting', @article = N'all';" 2>&1 | filter
publisher_side

echo
echo "== rpllab1: the push subscription of m05_Snapshot dropped at the publisher"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropsubscription @publication = N'm05_pubEnrollment', @subscriber = N'rpllab3',
         @destination_db = N'm05_Snapshot', @article = N'all';" 2>&1 | filter
echo "-- rpllab2: the agents of m05_pubEnrollment"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT j.name AS job FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
    WHERE c.name = N'REPL-Distribution' AND j.name LIKE N'%m05_pubEnrollment%' ORDER BY j.name;
    SELECT subscriber_db FROM distribution.dbo.MSdistribution_agents WHERE publication = N'm05_pubEnrollment';"
echo "-- rpllab3, m05_Snapshot"
subscriber_side m05_Snapshot
echo "-- rpllab3: sp_subscription_cleanup"
sql rpllab3 -d m05_Snapshot -Q "SET NOCOUNT ON;
    EXEC sys.sp_subscription_cleanup @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'm05_pubEnrollment';" 2>&1 | filter
subscriber_side m05_Snapshot

echo
echo "== After: what remains"
publisher_side
id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
    EXEC sys.sp_posttracertoken @publication = N'm05_pubEnrollment', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history WHERE parent_tracer_id = $id AND subscriber_commit IS NOT NULL" 1 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT a.subscriber_db, DATEDIFF(second, t.publisher_commit, h.subscriber_commit) AS overall_latency_s
    FROM dbo.MStracer_tokens t JOIN dbo.MStracer_history h ON h.parent_tracer_id = t.tracer_id
    JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id WHERE t.tracer_id = $id;"
