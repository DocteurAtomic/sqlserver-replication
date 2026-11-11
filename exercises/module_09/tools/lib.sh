# Sourced by the scripts of the exercise of module 9 (after setup/lib.sh): the names of the
# exercise and the readings its scripts share.
pub=ex_pubBilling
subdb=ex_billing
dist_agent() {  # id of the Distribution Agent of ex_billing, empty when there is none
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N'distribution') IS NOT NULL
        SELECT id FROM distribution.dbo.MSdistribution_agents WHERE publication = N'$pub' AND subscriber_db = N'$subdb';" | tr -d '[:space:]'
}
dist_job() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSdistribution_agents WHERE publication = N'$pub' AND subscriber_db = N'$subdb';" | tr -d '[:space:]'
}
job_running() {  # 1 when an Agent job of rpllab2 is running
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);" | tr -d '[:space:]'
}
pending() {  # the commands of ex_billing not yet delivered
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $(dist_agent);" | tr -d '[:space:]'
}
