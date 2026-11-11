#!/usr/bin/env bash
# Exercise of module 8, solution, incident 2. Plays the incident, then: the Distribution Agent
# fails in 20598 (MSrepl_errors), the command is read with sp_browsereplcmds by the xact_seqno of
# the 14151 row; the session is missing on ex_catalog. Repair the data: the row copied from
# rpllab1 to ex_catalog, then the agent delivers the update at its next retry. The job is
# started again if the agent stopped after the delivery.
# Usage: ./exercises/module_08/solution/2-row-not-found.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
m=$(now)
./exercises/module_08/incidents/2-row-not-found.sh
agent=$(dist_agent)
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSrepl_errors WHERE time >= '$m' AND error_code = '20598'" 1 240
x=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONVERT(varchar(30), xact_seqno, 1) FROM distribution.dbo.MSrepl_errors
    WHERE time >= '$m' AND error_code = '14151' AND xact_seqno IS NOT NULL ORDER BY id DESC;" | tr -d '[:space:]')
x=${x:0:22}
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    CREATE TABLE #c (xact_seqno varbinary(16), originator_srvname sysname NULL, originator_db sysname NULL, article_id int,
                     type int, partial_command bit, hashkey int, originator_publication_id int, originator_db_version int,
                     originator_lsn varbinary(16), command nvarchar(1024), command_id int);
    INSERT #c EXEC sys.sp_browsereplcmds @xact_seqno_start = N'$x', @xact_seqno_end = N'$x';
    SELECT command FROM #c;"
# sqlcmd -y 0, not sql(): by default sqlcmd cuts a variable-length value at 256 bytes (the Remarks of session 2000); quotes doubled for N'...'
j=$($engine exec -i rpllab1 /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -y 0 -d PachadataTraining -Q "SET NOCOUNT ON;
        SELECT (SELECT * FROM Course.Session WHERE SessionId = 2000 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES) AS j;" | tr -d '\r' | grep '^{' | sed "s/'/''/g")
r=$(now)
sql rpllab3 -d $subdb -Q "SET NOCOUNT ON; DECLARE @j nvarchar(max) = N'$j';
    INSERT Course.Session
    SELECT * FROM OPENJSON(@j) WITH (SessionId int, CourseId int, LanguageCode char(2), TrainingRoomId int, StartDate date,
        Price decimal(8, 2), Rating tinyint, StatusCode char(10), CreationDate date, Duration tinyint, IsInHouse bit,
        Remarks varchar(1500), TrainerId int, CompanyId int);"
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$r' AND comments LIKE N'%command(s) were delivered%'" 1 240
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM distribution.dbo.MSdistribution_history WHERE agent_id = $agent AND time >= '$r' AND runstatus = 2" 1 10 2>/dev/null || true
job=$(dist_job)
if [ "$(job_running "$job")" != 1 ]; then
    echo "The Distribution Agent stopped after the delivery: its job is started again."
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
    wait_for rpllab2 "SELECT $(echo "COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)")" 1 60
fi
wait_for rpllab2 "SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent" 0 120
echo "Incident 2 repaired: session 2000 on $subdb with the price of rpllab1."
