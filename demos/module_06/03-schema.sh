#!/usr/bin/env bash
# Module 6, clip 6.3. The table of the courses takes a column, WebSlug, for the addresses of the
# registration site. replicate_ddl as pubCatalog has it, never set by the course; ALTER TABLE ...
# ADD at the publisher, the command stored in the distribution database and the column at the
# subscriber; ALTER TABLE ... ALTER COLUMN (PlanningComments widened to varchar(3000)), also
# replicated; sp_rename of a published column, refused (Msg 15051). Then NOT FOR REPLICATION:
# two triggers on Course.Course at the subscriber, one of them NOT FOR REPLICATION, and which one
# fires for a change brought by the Distribution Agent and for a local change; what the default
# schema options leave out at the subscriber (identity, CHECK and FOREIGN KEY constraints); and
# sp_identitycolumnforreplication on the identity column of the publisher. Last, the reading
# that closes the module: what the site sees, and a tracer token. 99-cleanup.sh drops the column,
# sets PlanningComments and the identity back.
# Needs 00-setup.sh first; the final reading counts the titles that 02-articles.sh adds.
# Usage: ./demos/module_06/03-schema.sh     (with Podman: ENGINE=podman ./demos/module_06/03-schema.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
db=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSpublisher_databases WHERE publisher_db = N'PachadataTraining';" | tr -d '[:space:]')
lastx() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(42), MAX(xact_seqno), 1)
        FROM distribution.dbo.MSrepl_transactions WHERE publisher_database_id = $db;" | tr -d '[:space:]'
}
columns() {  # instance, database: the columns of Course.Course that the clip changes
    sql $1 -d $2 -Q "SET NOCOUNT ON;
        SELECT N'$1' AS instance, name AS [column], TYPE_NAME(user_type_id) AS type, max_length
        FROM sys.columns WHERE object_id = OBJECT_ID(N'Course.Course')
          AND name IN (N'PlanningComments', N'ProductionComments', N'WebSlug') ORDER BY column_id;"
}

echo "== rpllab1: replicate_ddl of pubCatalog"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; SELECT name, replicate_ddl FROM dbo.syspublications WHERE name = N'pubCatalog';"

echo
echo "== rpllab1: ALTER TABLE ... ADD"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; ALTER TABLE Course.Course ADD WebSlug varchar(100) NULL;"
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.sys.columns WHERE object_id = OBJECT_ID(N'PachaCatalog.Course.Course') AND name = N'WebSlug'" 1 120
columns rpllab3 PachaCatalog
echo "-- rpllab2: what the Log Reader Agent stored"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL,
                     article_id int, type int, partial_command bit, hashkey int, originator_publication_id int,
                     originator_db_version int, originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    DECLARE @x nchar(22) = N'${x:0:22}';
    INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = @x, @publisher_database_id = $db;
    -- One transaction per article that publishes the table: the ALTER TABLE, then the three
    -- procedures of the subscriber created again with the new column. First lines only.
    SELECT a.publication, c.article_id, COUNT(*) AS command_lines,
           SUM(IIF(c.command LIKE N'ALTER TABLE%', 1, 0)) AS alter_table,
           SUM(IIF(c.command LIKE N'create procedure%', 1, 0)) AS create_procedure
    FROM #c c JOIN dbo.MSarticles ar ON ar.article_id = c.article_id AND ar.publisher_db = N'PachadataTraining'
    JOIN dbo.MSpublications a ON a.publication_id = ar.publication_id
    WHERE c.xact_seqno > CONVERT(varbinary(16), @x, 1) GROUP BY a.publication, c.article_id ORDER BY a.publication;
    SELECT DISTINCT LEFT(command, 80) AS command FROM #c
    WHERE xact_seqno > CONVERT(varbinary(16), @x, 1) AND (command LIKE N'ALTER TABLE%' OR command LIKE N'create procedure%');"

echo
echo "== rpllab1: ALTER TABLE ... ALTER COLUMN"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; ALTER TABLE Course.Course ALTER COLUMN PlanningComments varchar(3000) NULL;"
wait_for rpllab3 "SELECT max_length FROM PachaCatalog.sys.columns WHERE object_id = OBJECT_ID(N'PachaCatalog.Course.Course') AND name = N'PlanningComments'" 3000 120
columns rpllab3 PachaCatalog

echo
echo "== rpllab1: sp_rename of a published column"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sp_rename N'Course.Course.ProductionComments', N'ProductionNotes', N'COLUMN';" 2>&1 | filter || true
columns rpllab1 PachadataTraining

echo
echo "== rpllab1: a value for the new column"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Course SET WebSlug = 'sql-server-replication' WHERE CourseId = 1;"
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Course WHERE CourseId = 1 AND WebSlug = 'sql-server-replication'" 1 120
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT N'rpllab3' AS instance, CourseId, WebSlug FROM Course.Course WHERE CourseId = 1;"

echo
echo "== rpllab3: two triggers on Course.Course, one NOT FOR REPLICATION"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    CREATE TABLE dbo.m06_CourseLog (LogId int IDENTITY CONSTRAINT pk_m06_CourseLog PRIMARY KEY, CourseId int NOT NULL,
                                    TriggerName sysname NOT NULL, LoggedBy sysname NOT NULL DEFAULT APP_NAME());
    EXEC (N'CREATE TRIGGER Course.m06_trg_Course_Always ON Course.Course AFTER UPDATE AS
            INSERT dbo.m06_CourseLog (CourseId, TriggerName) SELECT CourseId, N''m06_trg_Course_Always'' FROM inserted;');
    EXEC (N'CREATE TRIGGER Course.m06_trg_Course_NFR ON Course.Course AFTER UPDATE NOT FOR REPLICATION AS
            INSERT dbo.m06_CourseLog (CourseId, TriggerName) SELECT CourseId, N''m06_trg_Course_NFR'' FROM inserted;');
    SELECT name AS [trigger], is_not_for_replication FROM sys.triggers WHERE parent_id = OBJECT_ID(N'Course.Course');"
echo "-- rpllab1: a change at the publisher"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Course SET WebSlug = 'sql-server-replication-2025' WHERE CourseId = 1;"
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.dbo.m06_CourseLog" 1 120
echo "-- rpllab3: a local change"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    UPDATE Course.Course SET PlanningComments = PlanningComments WHERE CourseId = 2;
    SELECT LogId, CourseId, TriggerName, LoggedBy FROM dbo.m06_CourseLog ORDER BY LogId;"

echo
echo "== rpllab3: what the default schema options leave out"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    SELECT N'rpllab3' AS instance,
           (SELECT COUNT(*) FROM sys.identity_columns WHERE OBJECT_SCHEMA_NAME(object_id) = N'Course') AS identity_columns,
           (SELECT COUNT(*) FROM sys.check_constraints WHERE OBJECT_SCHEMA_NAME(parent_object_id) = N'Course') AS check_constraints,
           (SELECT COUNT(*) FROM sys.foreign_keys WHERE OBJECT_SCHEMA_NAME(parent_object_id) = N'Course') AS foreign_keys;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    SELECT N'rpllab1' AS instance,
           (SELECT COUNT(*) FROM sys.identity_columns WHERE object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'), OBJECT_ID(N'Course.Session'), OBJECT_ID(N'Course.CourseLanguage'))) AS identity_columns,
           (SELECT COUNT(*) FROM sys.check_constraints WHERE parent_object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'), OBJECT_ID(N'Course.Session'), OBJECT_ID(N'Course.CourseLanguage'))) AS check_constraints,
           (SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id IN (OBJECT_ID(N'Course.Category'), OBJECT_ID(N'Course.Course'), OBJECT_ID(N'Course.Session'), OBJECT_ID(N'Course.CourseLanguage'))) AS foreign_keys;
    SELECT a.name AS article, CONVERT(varchar(18), a.schema_option, 1) AS schema_option
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid WHERE p.name = N'pubCatalog' ORDER BY a.artid;"

echo
echo "== rpllab1: sp_identitycolumnforreplication"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DECLARE @o int = OBJECT_ID(N'Course.Course');
    SELECT N'before' AS [when], name AS identity_column, is_not_for_replication FROM sys.identity_columns WHERE object_id = @o;
    EXEC sys.sp_identitycolumnforreplication @object_id = @o, @value = 1;
    SELECT N'after' AS [when], name AS identity_column, is_not_for_replication FROM sys.identity_columns WHERE object_id = @o;"

echo
echo "== rpllab3: what the registration site sees at the end of the module"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM Course.Session) AS sessions,
           (SELECT COUNT(*) FROM Course.Session WHERE StatusCode = 'CANCELED') AS canceled,
           (SELECT COUNT(*) FROM Course.CourseLanguage) AS course_titles,
           COL_LENGTH(N'Course.Session', N'Remarks') AS remarks_length,
           COL_LENGTH(N'Course.Course', N'WebSlug') AS webslug_length;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM Course.Session WHERE StatusCode <> 'CANCELED') AS sessions_not_canceled_at_the_publisher,
           (SELECT COUNT(*) FROM Course.CourseLanguage) AS course_titles_at_the_publisher;"
id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
    EXEC sys.sp_posttracertoken @publication = N'pubCatalog', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history WHERE parent_tracer_id = $id AND subscriber_commit IS NOT NULL" 1 120
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_helptracertokenhistory @publication = N'pubCatalog', @tracer_id = $id;"
