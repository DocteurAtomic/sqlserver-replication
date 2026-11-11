#!/usr/bin/env bash
# Exercise of module 8, solution, incident 1. What the subscriber shows: the category X1 does
# not arrive, nothing is pending for ex_catalog, and sp_repltrans on PachadataTraining lists
# a transaction not yet read: the Log Reader Agent. Its job is disabled and stopped; enabled and
# started again, it reads the transaction, and the Distribution Agent delivers it.
# Usage: ./exercises/module_08/solution/1-log-reader.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
. exercises/module_08/incidents/lib.sh
job=$(logreader_job)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    CREATE TABLE #t (xdesid varbinary(10), xact_seqno varbinary(10)); INSERT #t EXEC sys.sp_repltrans;
    SELECT COUNT(*) AS transactions_not_read FROM #t;"
sql rpllab2 -Q "SET NOCOUNT ON; SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name = N'$job';
    EXEC msdb.dbo.sp_update_job @job_name = N'$job', @enabled = 1; EXEC msdb.dbo.sp_start_job @job_name = N'$job';"
wait_for rpllab3 "SELECT COUNT(*) FROM $subdb.Course.Category WHERE CategoryCode = 'X1'" 1 180
wait_for rpllab2 "SELECT ISNULL(SUM(UndelivCmdsInDistDB), 0) FROM distribution.dbo.MSdistribution_status WHERE agent_id = $(dist_agent)" 0 120
echo "Incident 1 repaired: X1 on $subdb."
