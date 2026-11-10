#!/usr/bin/env bash
# Module 3, clip 3.2. The Snapshot Agent of pubReference and what it writes. Run first without
# any subscription, it writes nothing ("no subscriptions needed initialization"): a snapshot
# publication created with the defaults (immediate_sync false) only writes a snapshot for a
# subscription waiting for one. sp_addsubscription, run by a sysadmin, also creates the
# Distribution Agent job and starts it, under the Agent service account and with Windows
# authentication to the subscriber: under Linux it cannot connect to rpllab3 (clip 3.3 gives it
# a SQL Server login). The Snapshot Agent then writes a snapshot into a sub-folder of the
# snapshot folder on the shared volume: .pre, .sch, .idx and .bcp files.
# Then the locks. A transaction left open on Reference.VatRate (an UPDATE that is rolled back)
# holds the agent up in the middle of its work, which lets us read its locks: with
# @sync_method = native (pubReference), the agent already holds a shared lock on the tables it
# has read, and an UPDATE of Reference.Country waits; with concurrent (m03_pubConcurrent,
# transactional), the agent waits for a schema modification lock (Sch-M) on VatRate while it
# activates the articles, already holds it on the other two, and the same UPDATE waits too. The
# writer gives up after 3 s (SET LOCK_TIMEOUT), the open transaction is ended by KILL, and the
# agent finishes. Last, without an open transaction, an UPDATE of Reference.Country every 20 ms
# during a snapshot: with native it waits for the whole generation, with concurrent a few
# hundred milliseconds at most. Nothing is written to PachadataTraining: every UPDATE is rolled
# back.
# Needs 01-publication.sql first.
# Usage: ./demos/module_03/02-snapshot-agent.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh

runs() {  # number of finished runs of the Snapshot Agent of a publication
    echo "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id
          WHERE a.publication = N'$1' AND h.runstatus IN (2, 5, 6)"
}
snapshot() {  # starts the Snapshot Agent of a publication and waits until it has finished
    local pub=$1 n
    n=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(runs $pub)" | tr -d '[:space:]')
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'$pub';"
    wait_for rpllab2 "$(runs $pub)" $((n + 1)) 180
}
history() {  # the last run of the Snapshot Agent, without the lines of each bcp part
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        DECLARE @start datetime = (SELECT MAX(h.time) FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
                                   WHERE a.publication = N'$1' AND h.runstatus = 1 AND h.comments = N'Starting agent.');
        SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, h.comments
        FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id
        WHERE a.publication = N'$1' AND h.time >= @start AND h.comments NOT LIKE N'%(part %'
        ORDER BY h.timestamp;"
}

echo "== rpllab1: the Snapshot Agent of pubReference, before any subscription"
snapshot pubReference
history pubReference

echo
echo "== rpllab1: sp_addsubscription, PachaReporting on rpllab3"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubReference', @subscriber = N'rpllab3',
         @destination_db = N'PachaReporting', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    SELECT a.name AS article, s.srvname AS subscriber, s.dest_db, s.status, s.sync_type
    FROM dbo.syssubscriptions s JOIN dbo.sysarticles a ON a.artid = s.artid
    JOIN dbo.syspublications p ON p.pubid = a.pubid
    WHERE p.name = N'pubReference' ORDER BY a.artid;"
echo "-- rpllab2: the Distribution Agent job sp_addsubscription created"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT a.name AS job, a.subscriber_db, a.subscriber_security_mode, s.freq_type, s.freq_subday_type
    FROM distribution.dbo.MSdistribution_agents a
    JOIN msdb.dbo.sysjobschedules js ON js.job_id = CAST(a.job_id AS uniqueidentifier)
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE a.subscriber_db = N'PachaReporting';"

echo
echo "== rpllab1: the Snapshot Agent again"
snapshot pubReference
history pubReference
echo "-- rpllab2: the Distribution Agent meanwhile"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE runstatus = 6" 1 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, h.comments
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'PachaReporting' ORDER BY h.timestamp;
    SELECT TOP (1) e.error_code, e.error_text FROM dbo.MSrepl_errors e WHERE e.error_code <> N'' ORDER BY e.id;"

echo
echo "== The files, in the snapshot folder of the shared volume"
dir=$($engine exec rpllab1 sh -c 'ls -d /var/opt/mssql/share/repldata/unc/RPLLAB1_PACHADATATRAINING_PUBREFERENCE/* | tail -1')
echo "$dir"
$engine exec rpllab1 sh -c "cd '$dir' && ls" | sed 's/.*\.//' | sort | uniq -c
$engine exec rpllab1 sh -c "cd '$dir' && ls -l Country_* City_3.* 'City_3#1.bcp'" | awk '{print $5, $9}'
for f in Country_2.pre Country_2.sch Country_2.idx; do
    echo "-- $f"
    $engine exec rpllab1 cat "$dir/$f" | iconv -f UTF-16 -t UTF-8 | tr -d '\r' | grep -v '^$'
done

# The locks. The object ids are read before the scene: a catalog view read while the agent
# waits for a schema lock would wait too.
ids=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(OBJECT_ID(N'Reference.Country'), ' ', OBJECT_ID(N'Reference.City'), ' ', OBJECT_ID(N'Reference.VatRate'));")
read -r country city vatrate <<< "$ids"
locks() {  # the publication; one scene, printed as it goes
    local pub=$1 n holder
    n=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(runs $pub)" | tr -d '[:space:]')
    echo
    echo "== rpllab1, session 1: a transaction left open on Reference.VatRate"
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; SET CONTEXT_INFO 0x6D30335F686F6C64;
        BEGIN TRAN; UPDATE Reference.VatRate SET Rate1 = Rate1 WHERE StartDate = '20140101';
        WAITFOR DELAY '00:03:00'; ROLLBACK;" > /dev/null 2>&1 &
    wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_requests WHERE SUBSTRING(context_info, 1, 8) = 0x6D30335F686F6C64" 1 30
    holder=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT session_id FROM sys.dm_exec_requests WHERE SUBSTRING(context_info, 1, 8) = 0x6D30335F686F6C64" | tr -d '[:space:]')
    echo "session $holder: UPDATE Reference.VatRate, transaction open"
    echo "== rpllab1: the Snapshot Agent of $pub"
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'$pub';"
    wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
                      WHERE r.blocking_session_id = $holder AND s.program_name LIKE N'%-$pub-%'" 1 60
    echo "== rpllab1: what the agent waits for, and the locks it holds"
    sql rpllab1 -Q "SET NOCOUNT ON;
        SELECT r.session_id, s.program_name, r.wait_type, r.blocking_session_id
        FROM sys.dm_exec_requests r JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
        WHERE r.blocking_session_id = $holder;
        SELECT l.request_session_id AS session_id,
               CASE l.resource_associated_entity_id WHEN $country THEN N'Reference.Country' WHEN $city THEN N'Reference.City'
                    WHEN $vatrate THEN N'Reference.VatRate' END AS table_name,
               l.request_mode, l.request_status, COUNT(*) AS locks
        FROM sys.dm_tran_locks l
        WHERE l.resource_database_id = DB_ID(N'PachadataTraining') AND l.resource_type = N'OBJECT'
          AND l.resource_associated_entity_id IN ($country, $city, $vatrate)
        GROUP BY l.request_session_id, l.resource_associated_entity_id, l.request_mode, l.request_status
        ORDER BY l.request_session_id, table_name, l.request_status;"
    echo "== rpllab1, session 2: UPDATE Reference.Country, 3 s at most"
    sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; SET LOCK_TIMEOUT 3000;
        DECLARE @t datetime2 = SYSDATETIME();
        BEGIN TRY
            BEGIN TRAN; UPDATE Reference.Country SET Capital = Capital WHERE CountryCode = 'FRA';
            PRINT CONCAT(N'UPDATE done in ', DATEDIFF(ms, @t, SYSDATETIME()), N' ms'); ROLLBACK;
        END TRY
        BEGIN CATCH
            PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N' after ', DATEDIFF(ms, @t, SYSDATETIME()), N' ms: ', ERROR_MESSAGE());
            IF @@TRANCOUNT > 0 ROLLBACK;
        END CATCH;"
    echo "== rpllab1: KILL $holder, the open transaction is rolled back"
    sql rpllab1 -Q "KILL $holder;"
    wait_for rpllab2 "$(runs $pub)" $((n + 1)) 180
    wait || true  # the session ended by KILL exits with an error
    history $pub | grep -E 'runstatus|----|Locking|Activated|Bulk copying snapshot data for article .Country|generated' || true
}
locks pubReference
locks m03_pubConcurrent

# Without an open transaction: a session updates one row of Reference.Country (rolled back)
# every 20 ms for as long as the Snapshot Agent is connected to the publisher, and keeps the
# longest wait. The probe starts before the agent and waits for its session to appear.
probe() {
    local pub=$1 n
    n=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(runs $pub)" | tr -d '[:space:]')
    sql rpllab1 -d PachadataTraining -h -1 > "$tmp" 2>&1 <<SQL &
SET NOCOUNT ON;
DECLARE @pub sysname = N'$pub', @i int = 0, @t datetime2, @d int, @max int = 0, @slow int = 0, @n int = 0;
WHILE @i < 600 AND NOT EXISTS (SELECT * FROM sys.dm_exec_sessions WHERE program_name LIKE N'%-' + @pub + N'-%')
BEGIN WAITFOR DELAY '00:00:00.050'; SET @i += 1; END;
DECLARE @start datetime2 = SYSDATETIME();
WHILE EXISTS (SELECT * FROM sys.dm_exec_sessions WHERE program_name LIKE N'%-' + @pub + N'-%')
      AND DATEDIFF(s, @start, SYSDATETIME()) < 120
BEGIN
    SET @t = SYSDATETIME();
    BEGIN TRAN; UPDATE Reference.Country SET Capital = Capital WHERE CountryCode = 'FRA'; ROLLBACK;
    SET @d = DATEDIFF(ms, @t, SYSDATETIME()); SET @n += 1;
    IF @d > @max SET @max = @d;
    IF @d > 100 SET @slow += 1;
    WAITFOR DELAY '00:00:00.020';
END;
SELECT CONCAT(@pub, N': ', @n, N' updates while the agent was connected (', DATEDIFF(ms, @start, SYSDATETIME()),
              N' ms), ', @slow, N' over 100 ms, the longest ', @max, N' ms');
SQL
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'$pub';" > /dev/null
    wait
    wait_for rpllab2 "$(runs $pub)" $((n + 1)) 180
    cat "$tmp"
}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo
echo "== rpllab1: UPDATE Reference.Country every 20 ms during a snapshot, twice for each method"
for pub in pubReference m03_pubConcurrent pubReference m03_pubConcurrent; do probe $pub; done
