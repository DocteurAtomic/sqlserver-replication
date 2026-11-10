#!/usr/bin/env bash
# Module 4, clip 4.3. The latency of pubCatalog. A tracer token (sp_posttracertoken) travels the
# path of a transaction; sp_helptracertokenhistory gives the time it took to the distributor
# and from there to the subscriber. Seven tokens with the default profiles, posted after a
# random pause so that they do not keep the same phase as the agents; then seven with
# -PollingInterval 1 added to the command line of the Log Reader Agent and of the Distribution
# Agent (default 5 s in both profiles), then the default given back. The two intervals add up.
# Then a transaction of 100,000 rows: 100,000 sessions inserted in one transaction (from 2030
# on, two rooms never booked the same day), then deleted in one transaction. During each, every
# second: the commands waiting for the subscriber (sp_replmonitorsubscriptionpendingcmds on the
# distributor), the rows the subscriber already has, and the memory of the distributor's
# container. A token posted after the transaction gives the latency it caused.
# Nothing is left in PachadataTraining: the 100,000 sessions are deleted by the script (and by
# 99-cleanup.sh if the script stops halfway).
# Needs 01-publication.sh first.
# Usage: ./demos/module_04/03-latency.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
logreader=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSlogreader_agents WHERE publisher_db = N'PachadataTraining';" | tr -d '[:space:]')
distrib=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'PachaCatalog';" | tr -d '[:space:]')
running() {
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
token() {  # posts one tracer token, waits for it at the subscriber, prints its history
    local id
    id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
        EXEC sys.sp_posttracertoken @publication = N'pubCatalog', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
    wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history WHERE parent_tracer_id = $id AND subscriber_commit IS NOT NULL" 1 ${1:-120}
    sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; EXEC sys.sp_helptracertokenhistory @publication = N'pubCatalog', @tracer_id = $id;"
}
tokens() {  # $1 tokens, each after a pause of 0 to 4 s
    local i
    echo "distributor_latency subscriber subscriber_db subscriber_latency overall_latency"
    for i in $(seq 1 $1); do sleep $((RANDOM % 5)); token; done
}
polling() {  # adds (1) or removes (default) -PollingInterval 1 on the two agents, and restarts them
    local j
    sql rpllab2 -Q "SET NOCOUNT ON;
        DECLARE @job sysname, @cmd nvarchar(max);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT j.name, s.command FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
            WHERE j.name IN (N'$logreader', N'$distrib') AND s.step_id = 2;
        OPEN c; FETCH c INTO @job, @cmd;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @cmd = REPLACE(@cmd, N' -PollingInterval 1', N'') + IIF(N'$1' = N'1', N' -PollingInterval 1', N'');
            EXEC msdb.dbo.sp_update_jobstep @job_name = @job, @step_id = 2, @command = @cmd;
            EXEC msdb.dbo.sp_stop_job @job_name = @job;
            FETCH c INTO @job, @cmd;
        END;"
    for j in $logreader $distrib; do
        wait_for rpllab2 "$(running $j)" 0 60
        sql rpllab2 -Q "EXEC msdb.dbo.sp_start_job @job_name = N'$j';"
    done
    sql rpllab2 -Q "SET NOCOUNT ON;
        SELECT j.name AS job, s.command FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
        WHERE j.name IN (N'$logreader', N'$distrib') AND s.step_id = 2 ORDER BY j.name;"
}
watch() {  # every second, until the subscriber has $1 sessions: pending commands, rows, memory
    local i p n m
    echo "time     pendingcmdcount estimatedprocesstime subscriber_rows rpllab2_memory"
    for i in $(seq 1 300); do
        p=$(sql rpllab2 -d distribution -h -1 -Q "SET NOCOUNT ON;
            EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
                 @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0;" | xargs)
        n=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachaCatalog.Course.Session WITH (NOLOCK);" | tr -d '[:space:]')
        m=$($engine stats --no-stream --format '{{.MemUsage}}' rpllab2)
        printf '%s %-36s %-15s %s\n' "$(date +%T)" "$p" "$n" "$m"
        [ "$n" = "$1" ] && return 0
        sleep 1
    done
    echo "watch: the subscriber still has $n sessions, $1 expected" >&2
    return 1
}

echo "== rpllab1: seven tracer tokens, default profiles"
tokens 7
echo "-- rpllab2: -PollingInterval in the default profiles of the two agents"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT CASE p.agent_type WHEN 2 THEN N'Log Reader' WHEN 3 THEN N'Distribution' END AS agent, a.parameter_name, a.value
    FROM msdb.dbo.MSagent_profiles p JOIN msdb.dbo.MSagent_parameters a ON a.profile_id = p.profile_id
    WHERE p.def_profile = 1 AND p.agent_type IN (2, 3) AND a.parameter_name = N'-PollingInterval' ORDER BY p.agent_type;"

echo
echo "== rpllab2: -PollingInterval 1 on the command line of the two agents"
polling 1
token > /dev/null   # the first token after a restart also measures the start of the agents
tokens 7
echo "== rpllab2: the default polling interval given back"
polling default
token > /dev/null

echo
echo "== rpllab1: 100,000 sessions in one transaction"
before=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session;" | tr -d '[:space:]')
echo "-- rpllab2: memory of the distributor before: $($engine stats --no-stream --format '{{.MemUsage}}' rpllab2)"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DECLARE @t datetime2 = SYSDATETIME();
    BEGIN TRAN;
    WITH cl AS (SELECT CourseId, LanguageCode, ROW_NUMBER() OVER (ORDER BY CourseId, LanguageCode) - 1 AS k, COUNT(*) OVER () AS n
                FROM Course.CourseLanguage),
         g AS (SELECT TOP (100000) ROW_NUMBER() OVER (ORDER BY d.Number, r.TrainingRoomId) - 1 AS i,
                      DATEADD(day, d.Number - 1, CAST('20300101' AS date)) AS StartDate, r.TrainingRoomId
               FROM Tools.Number AS d CROSS JOIN Reference.TrainingRoom AS r WHERE d.Number <= 600)
    INSERT Course.Session (CourseId, LanguageCode, TrainingRoomId, StartDate, Price, StatusCode, Duration, IsInHouse)
    SELECT cl.CourseId, cl.LanguageCode, g.TrainingRoomId, g.StartDate, 990.00, 'PLANNED', 3, 0
    FROM g JOIN cl ON cl.k = g.i % cl.n;
    PRINT CONCAT(@@ROWCOUNT, N' sessions inserted');
    COMMIT;
    PRINT CONCAT(N'committed in ', DATEDIFF(ms, @t, SYSDATETIME()), N' ms');"
echo "-- rpllab2 and rpllab3, every second"
token 300 > "$tmp" &
watch $((before + 100000))
wait
echo "-- rpllab1: the token posted after the commit"
echo "distributor_latency subscriber subscriber_db subscriber_latency overall_latency"
cat "$tmp"

echo
echo "== rpllab1: the 100,000 sessions deleted, in one transaction"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DECLARE @t datetime2 = SYSDATETIME();
    DELETE Course.Session WHERE StartDate >= '20300101';
    PRINT CONCAT(@@ROWCOUNT, N' sessions deleted in ', DATEDIFF(ms, @t, SYSDATETIME()), N' ms');"
echo "-- rpllab2 and rpllab3, every second"
token 300 > "$tmp" &
watch $before
wait
echo "-- rpllab1: the token posted after the commit"
echo "distributor_latency subscriber subscriber_db subscriber_latency overall_latency"
cat "$tmp"

echo
echo "== The last reading: nothing waiting, the same sessions on both sides"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_replmonitorsubscriptionpendingcmds @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @subscriber = N'rpllab3', @subscriber_db = N'PachaCatalog', @subscription_type = 0;"
for n in rpllab1 rpllab3; do
    db=$([ $n = rpllab1 ] && echo PachadataTraining || echo PachaCatalog)
    sql $n -d $db -Q "SET NOCOUNT ON; SELECT N'$n' AS instance, COUNT(*) AS sessions, CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS checksum FROM Course.Session;"
done
