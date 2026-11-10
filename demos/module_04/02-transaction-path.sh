#!/usr/bin/env bash
# Module 4, clip 4.2. The path of a transaction, from the log of the publisher to the subscriber.
# First on pubCatalog: one transaction corrects the price of ten sessions; the Log Reader Agent
# copies it to the distribution database (MSrepl_transactions, MSrepl_commands), where
# sp_browsereplcmds shows ten calls of sp_MSupd_CourseSession; the Distribution Agent applies
# them at the subscriber, where the snapshot created the sp_MS procedures. The prices are given
# back by 99-cleanup.sh (m04_Journal.dbo.SessionBefore).
# Then what the Log Reader Agent reads, on the database of the module, m04_Journal, never on
# PachadataTraining: publication m04_pubJournal of dbo.Note (immediate_sync, so that its
# articles are active without a subscription) and its own Log Reader Agent. While the agent is
# connected, sp_replcmds fails with Msg 18752. The job is disabled (so that nothing starts it
# again, an Agent restart included) and stopped; sp_replcmds, sp_replshowcmds and sp_replflush
# then run in one session of the publisher. sp_repldone is never called: it moves the point
# from which the log can be truncated. The job is enabled and started again, and the
# transaction read by hand reaches the distribution database all the same.
# Needs 01-publication.sh first.
# Usage: ./demos/module_04/02-transaction-path.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
pubdb() {  # id of a publisher database in the distribution database
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSpublisher_databases WHERE publisher_db = N'$1';" | tr -d '[:space:]'
}
lastx() {  # the last transaction of a publisher database in the distribution database
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(CONVERT(varchar(42), MAX(xact_seqno), 1), '0x00')
        FROM distribution.dbo.MSrepl_transactions WHERE publisher_database_id = $1;" | tr -d '[:space:]'
}
newer() {  # waits until a transaction newer than $2 reaches the distribution database
    wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSrepl_transactions
                      WHERE publisher_database_id = $1 AND xact_seqno > $2), 1, 0)" 1 120
}
browse() {  # the commands of the transactions newer than $2, as sp_browsereplcmds shows them
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        DECLARE @x nchar(22) = (SELECT CONVERT(nchar(22), MIN(xact_seqno), 1) FROM dbo.MSrepl_transactions
                                WHERE publisher_database_id = $1 AND xact_seqno > $2),
                @y nchar(22) = (SELECT CONVERT(nchar(22), MAX(xact_seqno), 1) FROM dbo.MSrepl_transactions
                                WHERE publisher_database_id = $1 AND xact_seqno > $2);
        CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL,
                         article_id int, type int, partial_command bit, hashkey int, originator_publication_id int,
                         originator_db_version int, originator_lsn varbinary(16), command nvarchar(1024), command_id int);
        INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = @x, @xact_seqno_end = @y, @publisher_database_id = $1;
        SELECT CONVERT(varchar(22), xact_seqno, 1) AS xact_seqno, command_id, article_id, command FROM #c ORDER BY xact_seqno, command_id;"
}
running() {  # 1 when an Agent job is running on rpllab2
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
prices() {  # the ten sessions on one instance
    local db=$([ $1 = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $1 -d $db -Q "SET NOCOUNT ON;
        SELECT N'$1' AS instance, SessionId, StartDate, Price FROM Course.Session
        WHERE SessionId IN (SELECT TOP (10) SessionId FROM Course.Session WHERE StartDate >= '20270301' ORDER BY StartDate, SessionId)
        ORDER BY SessionId;"
}

cat_db=$(pubdb PachadataTraining)
before=$(lastx $cat_db)
echo "== rpllab1: one transaction, the price of ten sessions"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRAN;
    WITH s AS (SELECT TOP (10) Price FROM Course.Session WHERE StartDate >= '20270301' ORDER BY StartDate, SessionId)
    UPDATE s SET Price = Price + 50;
    PRINT CONCAT(@@ROWCOUNT, N' rows updated');
    COMMIT;"
newer $cat_db $before

echo
echo "== rpllab2: the transaction in the distribution database"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT CONVERT(varchar(22), t.xact_seqno, 1) AS xact_seqno, CONVERT(char(23), t.entry_time, 121) AS entry_time,
           (SELECT COUNT(*) FROM dbo.MSrepl_commands c WHERE c.publisher_database_id = t.publisher_database_id
                                                         AND c.xact_seqno = t.xact_seqno) AS commands
    FROM dbo.MSrepl_transactions t WHERE t.publisher_database_id = $cat_db AND t.xact_seqno > $before;"
echo "-- rpllab2: sp_browsereplcmds"
browse $cat_db $before

echo
echo "== rpllab3: the ten prices at the subscriber"
want=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON;
    SELECT SUM(Price) FROM Course.Session WHERE SessionId IN (SELECT TOP (10) SessionId FROM Course.Session WHERE StartDate >= '20270301' ORDER BY StartDate, SessionId);" | tr -d '[:space:]')
wait_for rpllab3 "SELECT SUM(Price) FROM PachaCatalog.Course.Session WHERE SessionId IN (SELECT TOP (10) SessionId FROM PachaCatalog.Course.Session WHERE StartDate >= '20270301' ORDER BY StartDate, SessionId)" "$want" 120
prices rpllab1
prices rpllab3
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) runstatus, CONVERT(char(23), time, 121) AS time, comments FROM dbo.MSdistribution_history
    WHERE agent_id = (SELECT id FROM dbo.MSdistribution_agents WHERE subscriber_db = N'PachaCatalog')
      AND comments LIKE N'%transaction(s) with%' ORDER BY timestamp DESC;"
echo "-- rpllab3: the procedure that applied them, its first lines"
sql rpllab3 -d PachaCatalog -h -1 -Q "SET NOCOUNT ON; EXEC sys.sp_helptext N'dbo.sp_MSupd_CourseSession';" \
    | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -24

echo
echo "== rpllab1: the database of the module, published with its own Log Reader Agent"
sql rpllab1 -d m04_Journal -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm04_Journal', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addpublication @publication = N'm04_pubJournal', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @independent_agent = N'true', @immediate_sync = N'true';
    EXEC sys.sp_addpublication_snapshot @publication = N'm04_pubJournal', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm04_pubJournal', @article = N'Note', @source_owner = N'dbo', @source_object = N'Note';
    EXEC sys.sp_startpublication_snapshot @publication = N'm04_pubJournal';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
                  WHERE a.publication = N'm04_pubJournal' AND h.runstatus = 2" 1 180
job=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSlogreader_agents WHERE publisher_db = N'm04_Journal';" | tr -d '[:space:]')
jdb=$(pubdb m04_Journal)
sql rpllab2 -Q "SET NOCOUNT ON; SELECT name AS job, publisher_db FROM distribution.dbo.MSlogreader_agents ORDER BY id;"

echo
echo "== rpllab1: a note, then sp_replcmds while the agent is connected"
before=$(lastx $jdb)
sql rpllab1 -d m04_Journal -Q "SET NOCOUNT ON; INSERT dbo.Note (Body) VALUES (N'Room 3 closed on Friday');"
sql rpllab1 -d m04_Journal -Q "EXEC sys.sp_replcmds @maxtrans = 1;" 2>&1 || true
sql rpllab1 -Q "SET NOCOUNT ON; SELECT session_id, program_name FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader%' ORDER BY session_id;"
newer $jdb $before

echo
echo "== rpllab2: the job of the agent disabled, then stopped"
sql rpllab2 -Q "SET NOCOUNT ON;
    EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 0;
    EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
wait_for rpllab2 "$(running $job)" 0 60
sql rpllab2 -Q "SET NOCOUNT ON; SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name = N'$job';"

echo
echo "== rpllab1: two notes in one transaction, then what the agent would read, in one session"
before=$(lastx $jdb)
sql rpllab1 -d m04_Journal -Q "SET NOCOUNT ON;
    BEGIN TRAN;
    INSERT dbo.Note (Body) VALUES (N'Projector replaced in room 5'), (N'Coffee machine fixed');
    COMMIT;"
sql rpllab1 -d m04_Journal -Q "EXEC sys.sp_replcmds @maxtrans = 1;
    EXEC sys.sp_replshowcmds @maxtrans = 1;
    EXEC sys.sp_replflush;" | cut -c1-160
echo "-- rpllab2: nothing new in the distribution database"
sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), N' new transaction(s)') FROM distribution.dbo.MSrepl_transactions WHERE publisher_database_id = $jdb AND xact_seqno > $before;"

echo
echo "== rpllab2: the job enabled and started again"
sql rpllab2 -Q "SET NOCOUNT ON;
    EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 1;
    EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
newer $jdb $before
browse $jdb $before
