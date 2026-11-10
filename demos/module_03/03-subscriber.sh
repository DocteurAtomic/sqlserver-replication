#!/usr/bin/env bash
# Module 3, clip 3.3. The first subscriber. sp_addpushsubscription_agent gives the Distribution
# Agent that sp_addsubscription created a SQL Server login to rpllab3 and a schedule, once a
# night at 02:00 (@frequency_subday = 1; the default is every 5 minutes). Started at once
# instead of waiting for the night, the agent fails: the snapshot creates the tables, not their
# schema, and PachaReporting has no schema Reference. Once the schema is created, the next run
# delivers the snapshot. Then @pre_creation_cmd: with drop, the default, an index created at
# the subscriber disappears at the next delivery; with truncate, it stays. The script ends with
# the reading that shows the request met: the last line of the agent, and the same rows on both
# sides.
# Needs 02-snapshot-agent.sh first.
# Usage: ./demos/module_03/03-subscriber.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'PachaReporting';" | tr -d '[:space:]')
agent="SELECT id FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'PachaReporting'"
delivered="SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = ($agent) AND runstatus = 2 AND comments LIKE N'Applied the snapshot%'"
running="SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
         WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
           AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
start_agent() {  # starts the Distribution Agent now; a run still going (a retry) is stopped first
    if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $running" | tr -d '[:space:]')" != 0 ]; then
        sql rpllab2 -Q "EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
        wait_for rpllab2 "$running" 0 60
    fi
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpushsubscription_agent @publication = N'pubReference',
        @subscriber = N'rpllab3', @subscriber_db = N'PachaReporting';"
}
history() {  # the last run of the Distribution Agent, without the lines of each bcp part
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        DECLARE @start datetime = (SELECT MAX(time) FROM dbo.MSdistribution_history
                                   WHERE agent_id = ($agent) AND comments = N'Starting agent.');
        SELECT runstatus, CONVERT(char(23), time, 121) AS time, delivered_commands, comments
        FROM dbo.MSdistribution_history
        WHERE agent_id = ($agent) AND time >= @start AND comments NOT LIKE N'Bulk cop%'
        ORDER BY timestamp;"
}
snapshot() {  # a new snapshot of pubReference, then its delivery
    local n m
    n=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id WHERE a.publication = N'pubReference' AND h.runstatus = 2" | tr -d '[:space:]')
    m=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $delivered" | tr -d '[:space:]')
    sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'pubReference';"
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history h JOIN distribution.dbo.MSsnapshot_agents a ON a.id = h.agent_id WHERE a.publication = N'pubReference' AND h.runstatus = 2" $((n + 1)) 180
    start_agent
    wait_for rpllab2 "$delivered" $((m + 1)) 180
}
rows() {  # the rows of the four tables, rpllab1 then rpllab3
    local n db
    for n in rpllab1 rpllab3; do
        db=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaReporting)
        sql $n -d $db -Q "SET NOCOUNT ON;
            SELECT N'$n' AS instance, (SELECT COUNT(*) FROM Reference.Country) AS Country, (SELECT COUNT(*) FROM Reference.City) AS City,
                   (SELECT COUNT(*) FROM Reference.VatRate) AS VatRate, (SELECT COUNT(*) FROM Reference.CurrencyArchive) AS CurrencyArchive;"
    done
}
indexes() {
    sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
        SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS table_name, name AS index_name, type_desc, is_primary_key
        FROM sys.indexes WHERE object_id = OBJECT_ID(N'Reference.City') AND index_id > 0 ORDER BY index_id;"
}

echo "== rpllab1: sp_addpushsubscription_agent, a SQL Server login and once a night at 02:00"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpushsubscription_agent @publication = N'pubReference', @subscriber = N'rpllab3',
         @subscriber_db = N'PachaReporting', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab',
         @frequency_type = 4, @frequency_interval = 1, @frequency_subday = 1, @active_start_time_of_day = 020000;"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT a.name AS job, a.subscriber_security_mode, a.subscriber_login, s.freq_type, s.freq_subday_type, s.active_start_time
    FROM distribution.dbo.MSdistribution_agents a
    JOIN msdb.dbo.sysjobschedules js ON js.job_id = CAST(a.job_id AS uniqueidentifier)
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE a.subscriber_db = N'PachaReporting';"

echo
echo "== rpllab1: the Distribution Agent, now"
start_agent
wait_for rpllab2 "SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSdistribution_history WHERE agent_id = ($agent)
                  AND runstatus = 6 AND comments LIKE N'%schema name \"Reference\"%'), 1, 0)" 1 180
history
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (3) CONVERT(char(23), time, 121) AS time, error_code, error_text FROM dbo.MSrepl_errors ORDER BY id DESC;"

echo
echo "== rpllab3: CREATE SCHEMA Reference, then the agent again"
sql rpllab3 -d PachaReporting -Q "CREATE SCHEMA Reference;"
m=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $delivered" | tr -d '[:space:]')
start_agent
wait_for rpllab2 "$delivered" $((m + 1)) 180
history
rows
indexes

echo
echo "== rpllab3: an index for the reports of the finance department"
sql rpllab3 -d PachaReporting -Q "CREATE INDEX ix_City_CityName ON Reference.City (CityName);"
indexes
echo "== A new snapshot, delivered (@pre_creation_cmd = drop)"
snapshot
indexes

echo
echo "== rpllab1: @pre_creation_cmd = truncate for City"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    BEGIN TRY
        EXEC sys.sp_changearticle @publication = N'pubReference', @article = N'City', @property = N'pre_creation_cmd', @value = N'truncate';
    END TRY
    BEGIN CATCH
        PRINT CONCAT(N'Msg ', ERROR_NUMBER(), N': ', ERROR_MESSAGE());
        IF ERROR_NUMBER() <> 20608 THROW;
    END CATCH;
    IF @@TRANCOUNT > 0 ROLLBACK;
    EXEC sys.sp_changearticle @publication = N'pubReference', @article = N'City', @property = N'pre_creation_cmd', @value = N'truncate',
         @force_invalidate_snapshot = 1, @force_reinit_subscription = 1;
    SELECT name AS article, pre_creation_cmd FROM dbo.sysarticles WHERE pubid = (SELECT pubid FROM dbo.syspublications WHERE name = N'pubReference') ORDER BY artid;"
sql rpllab3 -d PachaReporting -Q "CREATE INDEX ix_City_CityName ON Reference.City (CityName);"
echo "== A new snapshot, delivered (@pre_creation_cmd = truncate)"
snapshot
indexes
history | grep -E 'runstatus|----|City_3|Delivered|Applied the snapshot' || true

echo
echo "== The last reading: the last line of the agent, and the rows on both sides"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT TOP (1) runstatus, CONVERT(char(23), time, 121) AS time, delivered_commands, comments
    FROM dbo.MSdistribution_history WHERE agent_id = ($agent) ORDER BY timestamp DESC;"
rows
