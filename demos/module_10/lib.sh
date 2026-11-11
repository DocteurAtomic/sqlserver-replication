# Sourced by the scripts of demos/module_10 (ci: skip, it does nothing alone), after
# setup/lib.sh: the jobs of the three agents of pubCatalog on rpllab2, and helpers.
logreader=RPLLAB1-PachadataTraining-1
snapshot=RPLLAB1-PachadataTraining-pubCatalog-1
distrib=rpllab1-PachadataTraining-pubCatalog-RPLLAB3-1
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (clip 10.3)
    grep -v "^DBCC\|^WARNING\|^$" || true
}
running() {  # the query that returns 1 while a job of rpllab2 runs
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
stop_job() {
    if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(running "$1")" | tr -d '[:space:]')" = 1 ]; then
        sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$1';" > /dev/null
        wait_for rpllab2 "$(running "$1")" 0 60
    fi
}
start_job() {
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$1';" > /dev/null
}
restart_job() { stop_job "$1"; start_job "$1"; }
since() {  # the current time of rpllab2, to read only the history written after it
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(char(23), SYSDATETIME(), 121);" | sed -n 1p
}
history() {  # history of an agent of rpllab2 written after a time: logreader, snapshot or a distribution job
    local q
    case $1 in
        logreader) q="FROM dbo.MSlogreader_history h WHERE" ;;
        snapshot)  q="FROM dbo.MSsnapshot_history h WHERE" ;;
        *)         q="FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id WHERE a.name = N'$1' AND" ;;
    esac
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT CONVERT(char(8), h.time, 108) AS time, h.runstatus, LEFT(h.comments, 200) AS comments
        $q h.time >= '$2' AND h.comments NOT LIKE N'<stats%' ORDER BY h.time, h.timestamp;"
}
errors() {  # MSrepl_errors written after a time
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT CONVERT(char(8), time, 108) AS time, error_code, LEFT(REPLACE(REPLACE(error_text, CHAR(13), N''), CHAR(10), N' '), 200) AS error_text
        FROM dbo.MSrepl_errors WHERE time >= '$1' AND error_code <> N'' ORDER BY id;"
}
agent_logins() {  # who the agents of pubCatalog are connected as, on the three instances
    for n in rpllab1 rpllab2 rpllab3; do
        sql $n -h -1 -Q "SET NOCOUNT ON;
            SELECT CONCAT(N'$n  ', s.login_name, N'  (', s.program_name, N')')
            FROM sys.dm_exec_sessions s
            WHERE s.program_name LIKE N'Repl-LogReader-%' OR s.program_name LIKE N'%PachadataTraining%pubCatalog%'
            ORDER BY s.program_name, s.login_name;"
    done | sed '/^$/d' | sort -u
}
