#!/usr/bin/env bash
# Module 6, clip 6.1. The registration site must not see canceled sessions, nor the internal
# remarks of a session. On pubCatalog, the article Session gets a row filter (sp_articlefilter,
# refused in Msg 20608 without @force_reinit_subscription) and loses the column Remarks
# (sp_articlecolumn), then its synchronization view is rebuilt (sp_articleview). A snapshot
# reinitializes the article Session alone: the distribution history shows which tables were
# copied again. Then four changes on rpllab1 in one batch: two inserts (one canceled), a session
# canceled, a canceled session reopened; the subscriber and the commands stored in the
# distribution database show what the Log Reader Agent made of them. Then the trap: publication
# m06_pubClause, whose article gets its filter from sp_addarticle @filter_clause alone, delivered
# to m06_Clause: the snapshot is filtered, the changes are not. Last, one UPDATE of every session
# and the number of commands it gives each article: the filter is evaluated by the Log Reader
# Agent, row by row; the same UPDATE stops the Distribution Agent of m06_Clause (Msg 20598), the
# canceled sessions left out of its snapshot having no row to update. m06_pubClause is then
# dropped. The prices and statuses are given back by 99-cleanup.sh.
# Needs 00-setup.sh first.
# Usage: ./demos/module_06/01-filter.sh     (with Podman: ENGINE=podman ./demos/module_06/01-filter.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
snapshot() {  # publication, subscription database: runs the Snapshot Agent and waits for the delivery
    local pub=$1 db=$2 m
    m=$(now)
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'$pub';"
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
                      WHERE a.publication = N'$pub' AND h.time >= '$m' AND h.runstatus = 2" 1 180
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                      WHERE a.subscriber_db = N'$db' AND h.time >= '$m' AND h.comments LIKE N'Delivered snapshot%'" 1 180
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT TOP (1) a.publication, h.comments AS snapshot_agent FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
        WHERE a.publication = N'$pub' AND h.time >= '$m' AND h.runstatus = 2 ORDER BY h.timestamp DESC;
        -- A concurrent snapshot copies a table in several parts: one line per table, parts added up.
        SELECT a.subscriber_db, x.table_copied, COUNT(*) AS parts,
               SUM(CAST(SUBSTRING(x.rest, 2, CHARINDEX(N' rows', x.rest) - 2) AS int)) AS rows_copied
        FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
        CROSS APPLY (SELECT SUBSTRING(h.comments, 30, CHARINDEX(N'''', h.comments, 30) - 30) AS table_copied,
                            SUBSTRING(h.comments, CHARINDEX(N'(', h.comments), 40) AS rest) x
        WHERE a.subscriber_db = N'$db' AND h.time >= '$m' AND h.comments LIKE N'Bulk copied data into table ''%'
        GROUP BY a.subscriber_db, x.table_copied ORDER BY x.table_copied;"
}
statuses() {  # instance, database: sessions by status
    sql $1 -d $2 -Q "SET NOCOUNT ON;
        SELECT N'$1' AS instance, DB_NAME() AS [database], StatusCode, COUNT(*) AS sessions
        FROM Course.Session GROUP BY StatusCode ORDER BY StatusCode;"
}
db=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSpublisher_databases WHERE publisher_db = N'PachadataTraining';" | tr -d '[:space:]')
lastx() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(42), MAX(xact_seqno), 1)
        FROM distribution.dbo.MSrepl_transactions WHERE publisher_database_id = $db;" | tr -d '[:space:]'
}

echo "== rpllab3: what the registration site sees today"
statuses rpllab3 PachaCatalog
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT COL_LENGTH(N'Course.Session', N'Remarks') AS remarks_length;"

echo
echo "== rpllab1: a row filter on a subscribed article, without the flags"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_articlefilter @publication = N'pubCatalog', @article = N'Session', @filter_name = N'FLTR_Session',
         @filter_clause = N'StatusCode <> ''CANCELED''';" 2>&1 | filter || true

echo
echo "== rpllab1: the row filter, the column filter and the synchronization view"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_articlefilter @publication = N'pubCatalog', @article = N'Session', @filter_name = N'FLTR_Session',
         @filter_clause = N'StatusCode <> ''CANCELED''', @force_reinit_subscription = 1;
    SELECT a.name AS article, s.status AS subscription_status
    FROM dbo.syssubscriptions s JOIN dbo.sysarticles a ON a.artid = s.artid JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE p.name = N'pubCatalog' AND s.srvid >= 0 ORDER BY a.artid;
    EXEC sys.sp_articlecolumn @publication = N'pubCatalog', @article = N'Session', @column = N'Remarks', @operation = N'drop';
    EXEC sys.sp_articleview @publication = N'pubCatalog', @article = N'Session', @view_name = N'SYNC_Session',
         @filter_clause = N'StatusCode <> ''CANCELED''';
    SELECT a.name AS article, OBJECT_SCHEMA_NAME(a.filter) + N'.' + OBJECT_NAME(a.filter) AS filter_procedure,
           CAST(a.filter_clause AS nvarchar(100)) AS filter_clause,
           OBJECT_SCHEMA_NAME(a.sync_objid) + N'.' + OBJECT_NAME(a.sync_objid) AS sync_view
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE p.name = N'pubCatalog' AND a.name = N'Session';
    SELECT OBJECT_DEFINITION(OBJECT_ID(N'dbo.FLTR_Session')) AS filter_procedure_text;" 2>&1 | filter

echo
echo "== rpllab1: a snapshot, and what it copies"
snapshot pubCatalog PachaCatalog
statuses rpllab3 PachaCatalog
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT COL_LENGTH(N'Course.Session', N'Remarks') AS remarks_length;"

echo
echo "== rpllab1: two new sessions, one canceled; session 17612 canceled; session 17572 reopened"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Session (CourseId, LanguageCode, StartDate, Price, StatusCode, Duration)
    VALUES (383, 'FR', '2031-01-06', 985, 'OPEN', 2), (383, 'FR', '2031-01-13', 985, 'CANCELED', 2);
    UPDATE Course.Session SET StatusCode = 'CANCELED' WHERE SessionId = 17612;
    UPDATE Course.Session SET StatusCode = 'OPEN' WHERE SessionId = 17572;
    SELECT N'rpllab1' AS instance, SessionId, StatusCode, StartDate FROM Course.Session
    WHERE SessionId IN (17572, 17612) OR SessionId > 19300 ORDER BY SessionId;"
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Session WHERE SessionId IN (17572, 19301)" 2 120
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Session WHERE SessionId = 17612" 0 120
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    SELECT N'rpllab3' AS instance, SessionId, StatusCode, StartDate FROM Course.Session
    WHERE SessionId IN (17572, 17612) OR SessionId > 19300 ORDER BY SessionId;"
echo "-- rpllab2: the commands stored for these changes"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL,
                     article_id int, type int, partial_command bit, hashkey int, originator_publication_id int,
                     originator_db_version int, originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    DECLARE @x nchar(22) = N'${x:0:22}';
    INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = @x, @publisher_database_id = $db;
    SELECT CONVERT(varchar(22), xact_seqno, 1) AS xact_seqno, LEFT(command, 140) AS command FROM #c
    WHERE xact_seqno > CONVERT(varbinary(16), @x, 1) ORDER BY xact_seqno, command_id;"

echo
echo "== rpllab1: publication m06_pubClause, a filter given to sp_addarticle alone"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'm06_pubClause', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'false';
    EXEC sys.sp_addpublication_snapshot @publication = N'm06_pubClause', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm06_pubClause', @article = N'Session', @source_owner = N'Course',
         @source_object = N'Session', @filter_clause = N'StatusCode <> ''CANCELED''';
    SELECT p.name AS publication, a.name AS article, a.filter AS filter_procedure_id, CAST(a.filter_clause AS nvarchar(100)) AS filter_clause
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE a.name = N'Session' ORDER BY p.name;
    EXEC sys.sp_addsubscription @publication = N'm06_pubClause', @subscriber = N'rpllab3',
         @destination_db = N'm06_Clause', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm06_pubClause', @subscriber = N'rpllab3',
         @subscriber_db = N'm06_Clause', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;" 2>&1 | filter
snapshot m06_pubClause m06_Clause
statuses rpllab3 m06_Clause

echo
echo "== rpllab1: a canceled session inserted, session 17613 canceled"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Session (CourseId, LanguageCode, StartDate, Price, StatusCode, Duration)
    VALUES (383, 'FR', '2031-01-20', 985, 'CANCELED', 2);
    UPDATE Course.Session SET StatusCode = 'CANCELED' WHERE SessionId = 17613;
    SELECT N'rpllab1' AS instance, SessionId, StatusCode FROM Course.Session WHERE SessionId IN (17613, 19303);"
wait_for rpllab3 "SELECT COUNT(*) FROM m06_Clause.Course.Session WHERE SessionId = 19303" 1 120
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Session WHERE SessionId = 17613" 0 120
sql rpllab3 -Q "SET NOCOUNT ON;
    SELECT N'm06_Clause' AS [database], SessionId, StatusCode FROM m06_Clause.Course.Session WHERE SessionId IN (17613, 19303)
    UNION ALL
    SELECT N'PachaCatalog', SessionId, StatusCode FROM PachaCatalog.Course.Session WHERE SessionId IN (17613, 19303);
    SELECT (SELECT COUNT(*) FROM m06_Clause.Course.Session WHERE StatusCode = 'CANCELED') AS canceled_in_m06_Clause,
           (SELECT COUNT(*) FROM PachaCatalog.Course.Session WHERE StatusCode = 'CANCELED') AS canceled_in_PachaCatalog;"

echo
echo "== rpllab1: one UPDATE of every priced session, and the commands of each article"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    UPDATE Course.Session SET Price = Price + 1 WHERE Price IS NOT NULL;
    SELECT @@ROWCOUNT AS rows_updated;"
# The Distribution Agent applies a transaction as a whole: once session 19301 has its new price
# in PachaCatalog, every command of the UPDATE is in the distribution database.
wait_for rpllab3 "SELECT Price FROM PachaCatalog.Course.Session WHERE SessionId = 19301" 986.00 180
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT p.publication, a.article, COUNT(*) AS commands
    FROM dbo.MSrepl_commands c
    JOIN dbo.MSarticles a ON a.article_id = c.article_id AND a.publisher_db = N'PachadataTraining'
    JOIN dbo.MSpublications p ON p.publication_id = a.publication_id
    WHERE c.publisher_database_id = $db
      AND c.xact_seqno = (SELECT MIN(xact_seqno) FROM dbo.MSrepl_transactions WHERE publisher_database_id = $db AND xact_seqno > $x)
    GROUP BY p.publication, a.article ORDER BY p.publication;"
echo "-- rpllab2: the Distribution Agent of m06_Clause"
# The canceled sessions were left out of the snapshot of m06_Clause, but their updates are not
# filtered: the agent finds no row to update and stops (Msg 20598).
wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.subscriber_db = N'm06_Clause' AND h.runstatus = 6), 1, 0)" 1 180
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.runstatus, CONVERT(char(23), h.time, 121) AS time, h.comments
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'm06_Clause' AND h.runstatus = 6 ORDER BY h.timestamp DESC;"

echo
echo "== rpllab1: m06_pubClause removed"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropsubscription @publication = N'm06_pubClause', @article = N'all', @subscriber = N'all';
    EXEC sys.sp_droppublication @publication = N'm06_pubClause';
    SELECT name FROM dbo.syspublications ORDER BY name;" 2>&1 | filter
