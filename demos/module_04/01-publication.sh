#!/usr/bin/env bash
# Module 4, clip 4.1. The catalog for the registration site, published step by step: the same
# calls as setup/repl-catalog.sql, with what each one leaves behind. The schema Course is created
# at the subscriber first (lesson of module 3). On rpllab1: the database marked for publication,
# the Log Reader Agent (one per published database, its job on the distributor), publication
# pubCatalog with the rule of the course (@status active, @sync_method concurrent, @allow_pull),
# its Snapshot Agent (run on demand), three articles and the commands they will use at the
# subscriber, then the push subscription and its Distribution Agent, continuous. Last, the
# initial snapshot, and the reading that shows it delivered.
# Needs 00-setup.sh first.
# Usage: ./demos/module_04/01-publication.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
agent_jobs() {  # the replication jobs on the distributor and their schedule
    sql rpllab2 -Q "SET NOCOUNT ON;
        SELECT j.name AS job, c.name AS category, s.freq_type, s.freq_subday_type, j.enabled
        FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
        LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
        LEFT JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
        WHERE c.name IN (N'REPL-LogReader', N'REPL-Snapshot', N'REPL-Distribution') ORDER BY c.name, j.name;"
}

echo "== rpllab3: the schema of the subscription database first"
sql rpllab3 -d PachaCatalog -Q "CREATE SCHEMA Course;"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT name FROM sys.schemas WHERE name = N'Course';"

echo
echo "== rpllab1: the database, then its Log Reader Agent"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'PachadataTraining', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_helplogreader_agent;" | cut -c1-200
echo "-- rpllab2"
agent_jobs

echo
echo "== rpllab1: publication pubCatalog"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'pubCatalog', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'false',
         @description = N'Catalog of PachaData for the registration site';
    EXEC sys.sp_addpublication_snapshot @publication = N'pubCatalog', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    SELECT name, repl_freq, status, sync_method, immediate_sync, independent_agent, allow_push, allow_pull, retention
    FROM dbo.syspublications WHERE name = N'pubCatalog';"

echo
echo "== rpllab1: the three articles"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
    EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Course', @source_owner = N'Course', @source_object = N'Course';
    EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'Session', @source_owner = N'Course', @source_object = N'Session';
    SELECT a.name AS article, CONVERT(varchar(18), a.schema_option, 1) AS schema_option,
           a.ins_cmd, a.upd_cmd, a.del_cmd
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE p.name = N'pubCatalog' ORDER BY a.artid;
    SELECT name, is_published FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'Course' ORDER BY name;"

echo
echo "== rpllab1: the push subscription and its Distribution Agent, continuous"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3',
         @destination_db = N'PachaCatalog', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'pubCatalog', @subscriber = N'rpllab3',
         @subscriber_db = N'PachaCatalog', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;"
echo "-- rpllab2"
agent_jobs

echo
echo "== rpllab1: the initial snapshot"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';"
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
agent="SELECT id FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'PachaCatalog'"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = ($agent)
                  AND comments LIKE N'Delivered snapshot%'" 1 180
echo "-- rpllab2: the Snapshot Agent, then the Distribution Agent"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, h.comments
    FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
    WHERE a.publication = N'pubCatalog' AND h.comments NOT LIKE N'%(part %' ORDER BY h.timestamp;
    SELECT runstatus, CONVERT(char(23), time, 121) AS time, delivered_commands, comments
    FROM dbo.MSdistribution_history
    WHERE agent_id = ($agent) AND comments NOT LIKE N'Bulk cop%' AND comments NOT LIKE N'Applied script%'
    ORDER BY timestamp;"
echo "-- rpllab1 and rpllab3: the rows on both sides"
for n in rpllab1 rpllab3; do
    db=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $n -d $db -Q "SET NOCOUNT ON;
        SELECT N'$n' AS instance, (SELECT COUNT(*) FROM Course.Category) AS Category,
               (SELECT COUNT(*) FROM Course.Course) AS Course, (SELECT COUNT(*) FROM Course.Session) AS Session;"
done
echo "-- rpllab3: what the snapshot created besides the tables"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    SELECT name FROM sys.procedures WHERE name LIKE N'sp_MS%' ORDER BY name;
    SELECT OBJECT_NAME(parent_object_id) AS table_name, name, type_desc FROM sys.objects
    WHERE type IN ('PK', 'F', 'UQ') ORDER BY 1, 2;
    SELECT OBJECT_NAME(object_id) AS table_name, name AS index_name, type_desc, is_unique, is_primary_key
    FROM sys.indexes WHERE object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'), OBJECT_ID(N'Course.Session')) AND index_id > 0
    ORDER BY 1, index_id;"
