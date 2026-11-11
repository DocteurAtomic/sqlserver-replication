#!/usr/bin/env bash
# Module 6, clip 6.2. The registration site wants the titles of the courses: Course.CourseLanguage
# joins pubCatalog. What adding an article asks depends on @immediate_sync, measured here in
# the two configurations of the course, both with concurrent snapshot processing.
# pubCatalog (immediate_sync false): sp_addarticle needs no flag and subscribes nobody; a
# snapshot taken then copies nothing; sp_addsubscription refuses the article alone (Msg 14100,
# concurrent) and takes @article = N'all'; the snapshot then covers the new article alone, and
# the distribution history shows that no other table was copied again.
# m06_pubImmediate (immediate_sync true), pushed to m06_Immediate: an article added before the
# first snapshot needs no flag; after it, sp_addarticle is refused in Msg 20607 until
# @force_invalidate_snapshot = 1, existing subscriptions get the article at once, and the
# snapshot is generated for every article but delivers the new one alone. Then the transaction
# a refused call leaves open inside TRY...CATCH: the next call of the same session succeeds
# inside it, is rolled back at the publisher when the session ends, and stays at the remote
# distributor, where the following sp_addarticle stumbles on it. Last, dropping an article
# (Msg 14046 while it is subscribed, then 20607).
# Needs 00-setup.sh first (01-filter.sh is not needed).
# Usage: ./demos/module_06/02-articles.sh     (with Podman: ENGINE=podman ./demos/module_06/02-articles.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
copied() {  # subscription database, mark: the tables copied since the mark, parts of a concurrent snapshot added up
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT a.subscriber_db, x.table_copied, COUNT(*) AS parts,
               SUM(CAST(SUBSTRING(x.rest, 2, CHARINDEX(N' rows', x.rest) - 2) AS int)) AS rows_copied
        FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
        CROSS APPLY (SELECT SUBSTRING(h.comments, 30, CHARINDEX(N'''', h.comments, 30) - 30) AS table_copied,
                            SUBSTRING(h.comments, CHARINDEX(N'(', h.comments), 40) AS rest) x
        WHERE a.subscriber_db = N'$1' AND h.time >= '$2' AND h.comments LIKE N'Bulk copied data into table ''%'
        GROUP BY a.subscriber_db, x.table_copied ORDER BY x.table_copied;"
}
snapshot() {  # publication: runs the Snapshot Agent, waits for it and prints its last message; sets $m
    m=$(now)
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'$1';"
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
                      WHERE a.publication = N'$1' AND h.time >= '$m' AND h.runstatus = 2" 1 180
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT TOP (1) a.publication, h.comments AS snapshot_agent FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
        WHERE a.publication = N'$1' AND h.time >= '$m' AND h.runstatus = 2 ORDER BY h.timestamp DESC;"
}
delivered() {  # subscription database: waits for the delivery of the snapshot started at $m
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                      WHERE a.subscriber_db = N'$1' AND h.time >= '$m' AND h.comments LIKE N'Delivered snapshot%'" 1 180
}
subscriptions() {  # publication: the subscription of each article, as the publisher knows it
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
        SELECT p.name AS publication, a.name AS article, s.dest_db, s.status AS subscription_status
        FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
        LEFT JOIN dbo.syssubscriptions s ON s.artid = a.artid AND s.srvid >= 0
        WHERE p.name = N'$1' ORDER BY a.artid;"
}

echo "== rpllab1: pubCatalog, immediate_sync false"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    SELECT name, immediate_sync, immediate_sync_ready, independent_agent, sync_method FROM dbo.syspublications WHERE name = N'pubCatalog';"

echo
echo "== rpllab1: the article CourseLanguage, no flag"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'CourseLanguage', @source_owner = N'Course',
         @source_object = N'CourseLanguage';" 2>&1 | filter
subscriptions pubCatalog
echo "-- rpllab1: a snapshot before any subscription to the article"
snapshot pubCatalog
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT OBJECT_ID(N'Course.CourseLanguage') AS courselanguage_at_the_subscriber;"

echo
echo "== rpllab1: the subscription to the new article"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3', @destination_db = N'PachaCatalog',
         @subscription_type = N'push', @sync_type = N'automatic', @article = N'CourseLanguage';" 2>&1 | filter || true
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3', @destination_db = N'PachaCatalog',
         @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';" 2>&1 | filter
subscriptions pubCatalog
snapshot pubCatalog
delivered PachaCatalog
copied PachaCatalog "$m"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT N'rpllab3' AS instance, COUNT(*) AS course_titles FROM Course.CourseLanguage;"
echo "-- rpllab2: every snapshot applied to PachaCatalog since 00-setup.sh, article by article"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT SUBSTRING(h.comments, 17, CHARINDEX(N'_', h.comments, 17) - 17) AS article, COUNT(*) AS snapshots_applied
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'PachaCatalog' AND h.comments LIKE N'Applied script ''%.pre'''
    GROUP BY SUBSTRING(h.comments, 17, CHARINDEX(N'_', h.comments, 17) - 17) ORDER BY article;"

echo
echo "== rpllab1: m06_pubImmediate, immediate_sync true, pushed to m06_Immediate"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'm06_pubImmediate', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'true';
    EXEC sys.sp_addpublication_snapshot @publication = N'm06_pubImmediate', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
    EXEC sys.sp_addsubscription @publication = N'm06_pubImmediate', @subscriber = N'rpllab3',
         @destination_db = N'm06_Immediate', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm06_pubImmediate', @subscriber = N'rpllab3',
         @subscriber_db = N'm06_Immediate', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
    SELECT name, immediate_sync, immediate_sync_ready FROM dbo.syspublications WHERE name = N'm06_pubImmediate';" 2>&1 | filter
echo "-- rpllab1: the article Course, before the first snapshot, no flag"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'Course', @source_owner = N'Course', @source_object = N'Course';" 2>&1 | filter
subscriptions m06_pubImmediate
snapshot m06_pubImmediate
delivered m06_Immediate
copied m06_Immediate "$m"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    SELECT name, immediate_sync_ready FROM dbo.syspublications WHERE name = N'm06_pubImmediate';"

echo
echo "== rpllab1: the article CourseLanguage, after the snapshot"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'CourseLanguage', @source_owner = N'Course',
         @source_object = N'CourseLanguage';" 2>&1 | filter || true
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'CourseLanguage', @source_owner = N'Course',
         @source_object = N'CourseLanguage', @force_invalidate_snapshot = 1;
    SELECT name, immediate_sync_ready FROM dbo.syspublications WHERE name = N'm06_pubImmediate';" 2>&1 | filter
subscriptions m06_pubImmediate
snapshot m06_pubImmediate
delivered m06_Immediate
copied m06_Immediate "$m"

echo
echo "== rpllab1: a refused call inside TRY...CATCH, then the right call in the same session"
# No -b here: the batch goes on after the CATCH, as a script that only prints the error would.
$engine exec -i rpllab1 /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -I -W -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRY
        EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'Domain', @source_owner = N'Course', @source_object = N'Domain';
    END TRY
    BEGIN CATCH
        SELECT ERROR_NUMBER() AS error, @@TRANCOUNT AS trancount_in_catch, XACT_STATE() AS xact_state;
    END CATCH;
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'Domain', @source_owner = N'Course', @source_object = N'Domain',
         @force_invalidate_snapshot = 1;
    SELECT @@TRANCOUNT AS trancount, (SELECT COUNT(*) FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                                      WHERE p.name = N'm06_pubImmediate' AND a.name = N'Domain') AS domain_in_this_session;" 2>&1 | filter
echo "-- rpllab1 and rpllab2, after the session ended"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    SELECT N'rpllab1' AS instance, a.name AS article FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE p.name = N'm06_pubImmediate' ORDER BY a.artid;"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT N'rpllab2' AS instance, a.article FROM dbo.MSarticles a JOIN dbo.MSpublications p ON p.publication_id = a.publication_id
    WHERE p.publication = N'm06_pubImmediate' ORDER BY a.article_id;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'm06_pubImmediate', @article = N'Domain', @source_owner = N'Course', @source_object = N'Domain',
         @force_invalidate_snapshot = 1;" 2>&1 | filter || true
echo
echo "== rpllab1: dropping the article CourseLanguage from m06_pubImmediate"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_droparticle @publication = N'm06_pubImmediate', @article = N'CourseLanguage';" 2>&1 | filter || true
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropsubscription @publication = N'm06_pubImmediate', @article = N'CourseLanguage',
         @subscriber = N'rpllab3', @destination_db = N'm06_Immediate';" 2>&1 | filter
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_droparticle @publication = N'm06_pubImmediate', @article = N'CourseLanguage';" 2>&1 | filter || true
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_droparticle @publication = N'm06_pubImmediate', @article = N'CourseLanguage', @force_invalidate_snapshot = 1;" 2>&1 | filter
subscriptions m06_pubImmediate
sql rpllab3 -d m06_Immediate -Q "SET NOCOUNT ON; SELECT N'rpllab3' AS instance, COUNT(*) AS rows_left_in_CourseLanguage FROM Course.CourseLanguage;"

