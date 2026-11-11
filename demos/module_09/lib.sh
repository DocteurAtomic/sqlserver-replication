# Sourced by the scripts of demos/module_09 (ci: skip, it does nothing alone), after
# setup/lib.sh: the Distribution Agent of m09_pubBilling, its job, and helpers.
job=rpllab1-m09_Billing-m09_pubBilling-RPLLAB3-2
logreader=RPLLAB1-m09_Billing-2
agent=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSdistribution_agents WHERE name = N'$job';" | tr -d '[:space:]')
running() {  # the query that returns 1 while the job of the Distribution Agent runs
    echo "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
          WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
            AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)"
}
stop_agent() {
    if [ "$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; $(running)" | tr -d '[:space:]')" = 1 ]; then
        sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
        wait_for rpllab2 "$(running)" 0 60
    fi
}
start_agent() {
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
    wait_for rpllab2 "$(running)" 1 60
}
restart() { stop_agent; start_agent; }
profile_id() {  # profile_id of a Distribution Agent profile, by name
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT profile_id FROM msdb.dbo.MSagent_profiles WHERE agent_type = 3 AND profile_name = N'$1';" | tr -d '[:space:]'
}
pending() {  # commands of m09_pubBilling not yet delivered to the subscriber
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $agent;" | tr -d '[:space:]'
}
agent_output() {  # the output file of the Distribution Agent (UTF-16), as UTF-8
    $engine exec rpllab2 cat /var/opt/mssql/log/m09_distrib.log 2>/dev/null | iconv -f UTF-16LE -t UTF-8 | tr -d '\r'
}
