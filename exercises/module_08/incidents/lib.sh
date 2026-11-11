# Sourced by the scripts of the exercise of module 8 (after setup/lib.sh): the names of the
# exercise and the readings its scripts share.
pub=ex_pubCatalog
subdb=ex_catalog
# The job of the Log Reader Agent of PachadataTraining, and the Distribution Agent of ex_catalog.
logreader_job() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSlogreader_agents WHERE publisher_db = N'PachadataTraining';" | tr -d '[:space:]'
}
dist_agent() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT id FROM distribution.dbo.MSdistribution_agents WHERE publication = N'$pub' AND subscriber_db = N'$subdb';" | tr -d '[:space:]'
}
dist_job() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM distribution.dbo.MSdistribution_agents WHERE publication = N'$pub' AND subscriber_db = N'$subdb';" | tr -d '[:space:]'
}
# 1 when an Agent job of rpllab2 is running.
job_running() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
        WHERE j.name = N'$1' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);" | tr -d '[:space:]'
}
# The commands of ex_catalog not yet delivered.
pending() {
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $(dist_agent);" | tr -d '[:space:]'
}
# The time on rpllab2, for the readings of the distribution database.
now() { sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d'; }
# Records that an incident was played (ex_incident.dbo.Played on rpllab1).
played() {
    sql rpllab1 -d ex_incident -Q "SET NOCOUNT ON; INSERT dbo.Played (step) VALUES ($1);"
}
