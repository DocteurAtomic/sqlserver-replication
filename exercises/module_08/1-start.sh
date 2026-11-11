#!/usr/bin/env bash
# Exercise of module 8, starting state, and the first incident. demos/module_08/99-cleanup.sh
# removes what the demos (or anything else) left; the exercise of module 4 and its solution are
# played again: ex_pubCatalog (Course.Category, Course.Course, Course.Session) pushed to
# ex_catalog on rpllab3. On rpllab1, the database ex_incident keeps the price of session 2000
# (given back by the cleanup) and the incidents played (dbo.Played). Then incident 1: the job of
# the Log Reader Agent of PachadataTraining disabled and stopped, and the category X1 inserted
# on rpllab1. The next incidents are played by incidents/2-row-not-found.sh and
# incidents/3-duplicate.sh, each once the previous one is repaired.
# demos/module_08/99-cleanup.sh removes everything at the end, ex_incident included.
# Usage: ./exercises/module_08/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_08/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
./demos/module_08/99-cleanup.sh > /dev/null
./exercises/module_04/1-start.sh > /dev/null
sql rpllab3 < exercises/module_04/solution/1-schema.sql > /dev/null
sql rpllab1 < exercises/module_04/solution/2-publication.sql > /dev/null
./exercises/module_04/solution/3-deliver.sh > /dev/null
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE ex_incident;"
sql rpllab1 -d ex_incident -Q "SET NOCOUNT ON;
    CREATE TABLE dbo.Played (step int NOT NULL CONSTRAINT pk_Played PRIMARY KEY,
                             played_at datetime NOT NULL CONSTRAINT df_Played DEFAULT GETDATE());
    SELECT SessionId, Price INTO dbo.SessionBefore FROM PachadataTraining.Course.Session WHERE SessionId = 2000;"
job=$(logreader_job)
sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 0;"
[ "$(job_running "$job")" = 1 ] && sql rpllab2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id
    WHERE j.name = N'$job' AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
      AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" 0 60
played 1
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('X1', 'Incident 1', 'Exercise of module 8');"
echo "Incident 1 played: the category X1 inserted on rpllab1 does not reach ex_catalog. Find out why and repair,"
echo "then play the next one: ./exercises/module_08/incidents/2-row-not-found.sh"
