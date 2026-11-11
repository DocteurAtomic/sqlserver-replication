# Sourced by the scripts of demos/module_13 (ci: skip, it does nothing alone), after
# setup/lib.sh: the jobs of m13_pubCatalog on rpllab2, and helpers.
logreader=RPLLAB1-m13_Catalog-1
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
start_job() { sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$1';" > /dev/null; }
since() {  # the current time of rpllab2, to read only the history written after it
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(char(23), SYSDATETIME(), 121);" | sed -n 1p
}
lr_history() {  # Log Reader Agent history written after a time
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT CONVERT(char(8), time, 108) AS time, runstatus, LEFT(comments, 110) AS comments
        FROM dbo.MSlogreader_history WHERE time >= '$1' AND comments NOT LIKE N'<stats%' ORDER BY time, timestamp;"
}
errors() {  # MSrepl_errors written after a time
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT CONVERT(char(8), time, 108) AS time, error_code, LEFT(REPLACE(REPLACE(error_text, CHAR(13), N''), CHAR(10), N' '), 110) AS error_text
        FROM dbo.MSrepl_errors WHERE time >= '$1' AND error_code <> N'' ORDER BY id;"
}
codes() {  # the categories of the module (M, R, S) in m13_Catalog on an instance
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$1  ', ISNULL(STRING_AGG(CategoryCode, ' ') WITHIN GROUP (ORDER BY CategoryCode), N'(none)'))
        FROM m13_Catalog.Course.Category WHERE CategoryCode LIKE N'[MRS][0-9]';"
}
logstate() {  # why the log of m13_Catalog cannot be truncated, and how much of it is active
    sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'rpllab1  log_reuse_wait_desc ', d.log_reuse_wait_desc, N', active VLFs ', s.active_vlf_count,
        N', active log ', CAST(s.active_log_size_mb AS decimal(9, 1)), N' MB')
        FROM sys.databases d CROSS APPLY sys.dm_db_log_stats(d.database_id) s WHERE d.name = N'm13_Catalog';"
}
state() {  # what replication leaves on the three instances
    local n out
    out=$(for n in rpllab1 rpllab2 rpllab3; do sql $n -h -1 < demos/module_13/state.sql; done | sed '/^$/d')
    if [ -n "$out" ]; then echo "$out"; else echo "(nothing on the three instances)"; fi
}
