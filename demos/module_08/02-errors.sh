#!/usr/bin/env bash
# Module 8, clip 8.2. The row not found and the duplicate, on pubCatalog. A session deleted by
# hand on rpllab3, its price raised on rpllab1: the Distribution Agent retries the command
# alone, then fails in 20598, and SQL Server Agent starts it again every minute. Where to read
# it: MSdistribution_history, MSrepl_errors (the 20598 row has no xact_seqno, the 14151 row of
# the same error has it), and the command itself with sp_browsereplcmds, by its xact_seqno or by
# @agent_id. Three ways out. Repair the data: the row copied from rpllab1 to rpllab3. Skip the
# error: -SkipErrors 20598 added to the command of the job, then a second session deleted on
# rpllab3 and changed on rpllab1, skipped; a category inserted on both sides, a duplicate
# (2601, the subscriber has a unique index and no primary key constraint) that -SkipErrors 20598
# does not skip; the profile "Continue on data consistency errors." (-SkipErrors
# 2601:2627:20598) skips it. What is lost: the session missing on rpllab3, the category of
# rpllab3 kept. Reinitializing, the third way, is clip 8.4. The job and the profile are set back.
# The prices are given back by 99-cleanup.sh (m08_Journal.dbo.SessionBefore); the subscriber
# keeps its two differences for clip 8.3.
# Needs 00-setup.sh first.
# Usage: ./demos/module_08/02-errors.sh     (with Podman: ENGINE=podman ./demos/module_08/02-errors.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
job=rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1
agent=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSdistribution_agents WHERE name = N'$job';" | tr -d '[:space:]')
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
running() {
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
history() {  # the last lines of the Distribution Agent of pubCatalog since a time
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT TOP ($2) time, runstatus, error_id, LEFT(comments, 120) AS comments FROM dbo.MSdistribution_history
        WHERE agent_id = $agent AND time >= '$1' ORDER BY time DESC, timestamp DESC;"
}
errors() {
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT id, time, error_code, CONVERT(varchar(30), xact_seqno, 1) AS xact_seqno, command_id, LEFT(error_text, 110) AS error_text
        FROM dbo.MSrepl_errors WHERE time >= '$1' ORDER BY time, id;"
}
restart() {  # the job of the Distribution Agent stopped if it runs, then started, until it is idle or running
    local t
    if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(running)" | tr -d '[:space:]')" = 1 ]; then
        sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';"
        wait_for rpllab2 "$(running)" 0 60
    fi
    t=$(now)
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
    wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$t' AND runstatus IN (3, 4)" 1 120
}
session_json() {  # one session of rpllab1, as JSON
    # sqlcmd -y 0: by default sqlcmd cuts a variable-length value at 256 bytes (session 2000 lost the end of its Remarks); quotes doubled for N'...'
    $engine exec -i rpllab1 /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -y 0 -d PachadataTraining -Q "SET NOCOUNT ON;
        SELECT (SELECT * FROM Course.Session WHERE SessionId = $1 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) AS j;" | tr -d '\r' | grep '^{' | sed "s/'/''/g"
}
compare() {  # a session and the category Z8 on both sides
    for n in rpllab1 rpllab3; do
        db=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
        sql $n -d $db -Q "SET NOCOUNT ON;
            SELECT N'$n' AS instance, SessionId, Price FROM Course.Session WHERE SessionId IN ($1) ORDER BY SessionId;
            SELECT N'$n' AS instance, CategoryCode, Label FROM Course.Category WHERE CategoryCode = 'Z8';"
    done
}

echo "== rpllab3: session 1000 deleted by hand"
m=$(now)
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; DELETE Course.Session WHERE SessionId = 1000; SELECT @@ROWCOUNT AS deleted_on_rpllab3;"
echo "== rpllab1: its price raised by 1 at $m"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Session SET Price = Price + 1 WHERE SessionId = 1000;"
s=$(date +%s)
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSrepl_errors WHERE time >= '$m' AND error_code = '20598'" 1 240
echo "20598 written $(( $(date +%s) - s )) s after the update"
history "$m" 3
errors "$m"
echo "-- the job: running, and its retries"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT js.step_name, js.retry_attempts, js.retry_interval FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
    WHERE j.name = N'$job' AND js.step_id = 2;
    $(running);"

echo
echo "== rpllab2: the failing command, by the xact_seqno of the 14151 row"
x=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONVERT(varchar(30), xact_seqno, 1) FROM distribution.dbo.MSrepl_errors
    WHERE time >= '$m' AND error_code = '14151' AND xact_seqno IS NOT NULL ORDER BY id DESC;" | tr -d '[:space:]')
x=${x:0:22}
echo "xact_seqno $x"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL, article_id int,
                     type int, partial_command bit, hashkey int, originator_publication_id int, originator_db_version int,
                     originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = N'$x', @xact_seqno_end = N'$x';
    SELECT CONVERT(varchar(22), xact_seqno, 1) AS xact_seqno, article_id, command_id, command FROM #c;"
echo "-- the same, by @agent_id: every command not yet delivered to the subscription"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL, originator_id int,
                     type int, partial_command bit, hashkey int, originator_publication_id int, originator_db_version int,
                     originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    INSERT #c EXEC sys.sp_browsereplcmds @agent_id = $agent;
    SELECT COUNT(*) AS commands, SUM(IIF(command LIKE N'{CALL %', 1, 0)) AS calls FROM #c;
    SELECT CONVERT(varchar(22), xact_seqno, 1) AS xact_seqno, command_id, command FROM #c WHERE command LIKE N'{CALL %';"

echo
echo "== way 1: repair the data. Session 1000 copied from rpllab1 to rpllab3"
r=$(now)
j=$(session_json 1000)
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; DECLARE @j nvarchar(max) = N'$j';
    INSERT Course.Session
    SELECT * FROM OPENJSON(@j) WITH (SessionId int, CourseId int, LanguageCode char(2), TrainingRoomId int, StartDate date,
        Price decimal(8, 2), Rating tinyint, StatusCode char(10), CreationDate date, Duration tinyint, IsInHouse bit,
        Remarks varchar(1500), TrainerId int, CompanyId int);
    SELECT SessionId, Price, StatusCode FROM Course.Session WHERE SessionId = 1000;"
s=$(date +%s)
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$r' AND comments LIKE N'%command(s) were delivered%'" 1 240
echo "delivered $(( $(date +%s) - s )) s after the repair"
history "$r" 4
echo "-- the job, after the delivery"
sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'job running: ', ($(running)));"
restart
history "$r" 1

echo
echo "== way 2: skip the error. -SkipErrors 20598 added to the command of the job"
sql rpllab2 -Q "SET NOCOUNT ON;
    DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                                WHERE j.name = N'$job' AND js.step_id = 2);
    SET @c = @c + N' -SkipErrors 20598';
    EXEC msdb.dbo.sp_update_jobstep @job_name = N'$job', @step_id = 2, @command = @c;
    SELECT RIGHT(js.command, 60) AS end_of_command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
    WHERE j.name = N'$job' AND js.step_id = 2;"
restart
m=$(now)
echo "== rpllab3: session 1001 deleted; rpllab1: its price raised by 1"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; DELETE Course.Session WHERE SessionId = 1001;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Session SET Price = Price + 1 WHERE SessionId = 1001;"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'%command(s) were delivered%'" 1 120
history "$m" 3
errors "$m"
echo
echo "== the duplicate: category Z8 inserted on rpllab3, then on rpllab1"
m=$(now)
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('Z8', 'Written on rpllab3', 'Clip 8.2');"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('Z8', 'Written on rpllab1', 'Clip 8.2');"
s=$(date +%s)
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSrepl_errors WHERE time >= '$m' AND error_code IN ('2601', '2627')" 1 240
echo "duplicate key error written $(( $(date +%s) - s )) s after the insert"
history "$m" 2
errors "$m"
echo "-- the indexes of Course.Category on rpllab3, and the schema option of the article"
sql rpllab3 -d PachaCatalog -Q "SET NOCOUNT ON; SELECT name, type_desc, is_unique, is_primary_key FROM sys.indexes WHERE object_id = OBJECT_ID(N'Course.Category') AND index_id > 0;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; SELECT a.name, CONVERT(varchar(20), CAST(a.schema_option AS varbinary(8)), 1) AS schema_option FROM dbo.sysarticles a
    JOIN dbo.syspublications p ON p.pubid = a.pubid WHERE p.name = N'pubCatalog' AND a.name = N'Category';"

echo
echo "== the profile Continue on data consistency errors."
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @p int = (SELECT profile_id FROM msdb.dbo.MSagent_profiles WHERE agent_type = 3 AND profile_name = N'Continue on data consistency errors.');
    SELECT p.profile_id, p.profile_name, a.parameter_name, a.value FROM msdb.dbo.MSagent_profiles p
    JOIN msdb.dbo.MSagent_parameters a ON a.profile_id = p.profile_id WHERE p.profile_id = @p AND a.parameter_name = N'-SkipErrors';
    EXEC sys.sp_update_agent_profile @agent_type = 3, @agent_id = $agent, @profile_id = @p;
    SELECT name, profile_id FROM dbo.MSdistribution_agents WHERE id = $agent;" | grep -v 'is_reloadable'
echo "-- -SkipErrors 20598 taken off the command of the job: the command line wins over the profile"
sql rpllab2 -Q "SET NOCOUNT ON;
    DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                                WHERE j.name = N'$job' AND js.step_id = 2);
    SET @c = REPLACE(@c, N' -SkipErrors 20598', N'');
    EXEC msdb.dbo.sp_update_jobstep @job_name = N'$job', @step_id = 2, @command = @c;"
m=$(now)
restart
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$m' AND comments LIKE N'%command(s) were delivered%'" 1 120
history "$m" 4
errors "$m"
echo
echo "== what the skipped errors leave"
compare 1000,1001
echo
echo "== rpllab2: the default profile and the job set back"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    DECLARE @p int = (SELECT profile_id FROM msdb.dbo.MSagent_profiles WHERE agent_type = 3 AND def_profile = 1);
    EXEC sys.sp_update_agent_profile @agent_type = 3, @agent_id = $agent, @profile_id = @p;
    SELECT a.name, p.profile_name FROM dbo.MSdistribution_agents a JOIN msdb.dbo.MSagent_profiles p ON p.profile_id = a.profile_id WHERE a.id = $agent;" | grep -v 'is_reloadable'
restart
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0;"
