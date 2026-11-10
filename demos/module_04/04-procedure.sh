#!/usr/bin/env bash
# Module 4, clip 4.4. Publishing the execution of a procedure. Course.m04_RaiseSessionPrices
# raises the price of every session by a percentage: 19,300 rows. Published as an article of
# type 'serializable proc exec' in pubCatalog, it needs a subscription to the new article
# (with concurrent snapshot processing, sp_addsubscription only takes @article = N'all',
# Msg 14100) and a snapshot, which creates the procedure at the subscriber. Then the
# procedure is run three ways, and the commands of each transaction are counted in the
# distribution database: on its own (19,300 calls of sp_MSupd_CourseSession), inside a
# serializable transaction (one call of the procedure), and with the SET TRANSACTION ISOLATION
# LEVEL inside the procedure (19,300 again). Last, the procedure dropped at the subscriber: the
# Distribution Agent fails with Msg 2812, and runs again once the procedure is back. The prices
# are given back by 99-cleanup.sh, which also drops the procedure.
# Needs 01-publication.sh first.
# Usage: ./demos/module_04/04-procedure.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
db=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSpublisher_databases WHERE publisher_db = N'PachadataTraining';" | tr -d '[:space:]')
agent="SELECT id FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'PachaCatalog'"
lastx() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(42), MAX(xact_seqno), 1)
        FROM distribution.dbo.MSrepl_transactions WHERE publisher_database_id = $db;" | tr -d '[:space:]'
}
counted() {  # waits for the transactions newer than $1, then counts their commands
    wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSrepl_transactions
                      WHERE publisher_database_id = $db AND xact_seqno > $1), 1, 0)" 1 120
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT CONVERT(varchar(22), t.xact_seqno, 1) AS xact_seqno, COUNT(c.command_id) AS commands
        FROM dbo.MSrepl_transactions t JOIN dbo.MSrepl_commands c
          ON c.publisher_database_id = t.publisher_database_id AND c.xact_seqno = t.xact_seqno
        WHERE t.publisher_database_id = $db AND t.xact_seqno > $1 GROUP BY t.xact_seqno ORDER BY t.xact_seqno;"
}
same() {  # waits until the sessions have the same prices on both sides, then shows them
    local want
    want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT SUM(Price) FROM PachadataTraining.Course.Session;" | tr -d '[:space:]')
    wait_for rpllab3 "SELECT SUM(Price) FROM PachaCatalog.Course.Session" "$want" ${1:-180}
    for n in rpllab1 rpllab3; do
        local d=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
        sql $n -d $d -Q "SET NOCOUNT ON; SELECT N'$n' AS instance, COUNT(*) AS sessions, SUM(Price) AS total_price FROM Course.Session;"
    done
}
proc_text="CREATE PROCEDURE Course.m04_RaiseSessionPrices @percent decimal(5, 2)
AS
SET NOCOUNT ON;
UPDATE Course.Session SET Price = Price * (1 + @percent / 100) WHERE Price IS NOT NULL;"

echo "== rpllab1: the procedure, published for its execution"
sql rpllab1 -d PachadataTraining -Q "$proc_text"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addarticle @publication = N'pubCatalog', @article = N'm04_RaiseSessionPrices',
         @source_owner = N'Course', @source_object = N'm04_RaiseSessionPrices', @type = N'serializable proc exec';
    SELECT a.name AS article, a.type, CONVERT(varchar(18), a.schema_option, 1) AS schema_option
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid WHERE p.name = N'pubCatalog' ORDER BY a.artid;"
echo "-- rpllab1: the subscription to the new article"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRY
        EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3', @destination_db = N'PachaCatalog',
             @subscription_type = N'push', @sync_type = N'automatic', @article = N'm04_RaiseSessionPrices';
    END TRY
    BEGIN CATCH
        PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
        IF ERROR_NUMBER() <> 14100 THROW;
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3', @destination_db = N'PachaCatalog',
         @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    SELECT a.name AS article, s.status FROM dbo.syssubscriptions s JOIN dbo.sysextendedarticlesview a ON a.artid = s.artid
    ORDER BY a.artid;"
echo "-- rpllab1: a snapshot of the new article"
n=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id WHERE a.publication = N'pubCatalog' AND h.runstatus = 2" | tr -d '[:space:]')
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id WHERE a.publication = N'pubCatalog' AND h.runstatus = 2" $((n + 1)) 180
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.sys.procedures WHERE name = N'm04_RaiseSessionPrices'" 1 180
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.runstatus, h.comments FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
    WHERE a.publication = N'pubCatalog' ORDER BY h.timestamp DESC;"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT SCHEMA_NAME(schema_id) AS [schema], name FROM sys.procedures WHERE name = N'm04_RaiseSessionPrices';"

echo
echo "== rpllab1: EXEC on its own, 1 %"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET XACT_ABORT ON; EXEC Course.m04_RaiseSessionPrices @percent = 1;"
counted $x
same

echo
echo "== rpllab1: EXEC inside a serializable transaction, 1 %"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET XACT_ABORT ON;
    BEGIN TRAN;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    EXEC Course.m04_RaiseSessionPrices @percent = 1;
    COMMIT;"
counted $x
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @x nchar(22) = (SELECT CONVERT(nchar(22), MAX(xact_seqno), 1) FROM dbo.MSrepl_transactions WHERE publisher_database_id = $db);
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL,
                     article_id int, type int, partial_command bit, hashkey int, originator_publication_id int,
                     originator_db_version int, originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = @x, @xact_seqno_end = @x, @publisher_database_id = $db;
    SELECT article_id, command FROM #c;"
same

echo
echo "== rpllab1: the SET TRANSACTION ISOLATION LEVEL moved into the procedure"
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "ALTER PROCEDURE Course.m04_RaiseSessionPrices @percent decimal(5, 2)
AS
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
UPDATE Course.Session SET Price = Price * (1 + @percent / 100) WHERE Price IS NOT NULL;"
counted $x
wait_for rpllab3 "SELECT IIF(EXISTS (SELECT * FROM PachaCatalog.sys.sql_modules WHERE object_id = OBJECT_ID(N'PachaCatalog.Course.m04_RaiseSessionPrices')
                  AND definition LIKE N'%ISOLATION LEVEL SERIALIZABLE%'), 1, 0)" 1 120
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "SET XACT_ABORT ON; EXEC Course.m04_RaiseSessionPrices @percent = 1;"
counted $x
same
x=$(lastx)
sql rpllab1 -d PachadataTraining -Q "${proc_text/CREATE PROCEDURE/ALTER PROCEDURE}"
counted $x
wait_for rpllab3 "SELECT IIF(EXISTS (SELECT * FROM PachaCatalog.sys.sql_modules WHERE object_id = OBJECT_ID(N'PachaCatalog.Course.m04_RaiseSessionPrices')
                  AND definition LIKE N'%ISOLATION LEVEL SERIALIZABLE%'), 1, 0)" 0 120

echo
echo "== rpllab3: the procedure dropped at the subscriber, then the same call on rpllab1"
sql rpllab3 -d PachaCatalog -Q "DROP PROCEDURE Course.m04_RaiseSessionPrices;"
sql rpllab1 -d PachadataTraining -Q "SET XACT_ABORT ON;
    BEGIN TRAN;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    EXEC Course.m04_RaiseSessionPrices @percent = 1;
    COMMIT;"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSrepl_errors WHERE error_code = N'2812' AND time > DATEADD(minute, -5, GETDATE())" 1 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (2) CONVERT(char(23), time, 121) AS time, error_code, error_text FROM dbo.MSrepl_errors
    WHERE error_code IN (N'2812', N'14151') ORDER BY id DESC;"
echo "-- rpllab3: the procedure created again, from the publisher's definition"
sql rpllab3 -d PachaCatalog -Q "$proc_text"
same
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) runstatus, CONVERT(char(23), time, 121) AS time, comments FROM dbo.MSdistribution_history
    WHERE agent_id = ($agent) AND comments LIKE N'%transaction(s) with%' ORDER BY timestamp DESC;"
