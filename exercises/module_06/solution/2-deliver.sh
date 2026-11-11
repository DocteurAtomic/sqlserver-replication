#!/usr/bin/env bash
# Exercise of module 6, solution: the snapshot of the new article and of the filtered article,
# then the canceled session. Starts the Snapshot Agent of ex_pubCatalog and waits until the
# Distribution Agent has delivered it to ex_catalog; cancels session 17622 on rpllab1 and waits
# until it has left ex_catalog.
# Usage: ./exercises/module_06/solution/2-deliver.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
m=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), GETDATE(), 121);" | tr -d '\r' | sed '/^$/d')
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubCatalog';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.subscriber_db = N'ex_catalog' AND h.time >= '$m' AND h.comments LIKE N'Delivered snapshot%'" 1 180
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; UPDATE Course.Session SET StatusCode = 'CANCELED' WHERE SessionId = 17622;"
wait_for rpllab3 "SELECT COUNT(*) FROM ex_catalog.Course.Session WHERE SessionId = 17622" 0 120
sql rpllab3 -d ex_catalog -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM Course.CourseLanguage) AS course_titles,
           (SELECT COUNT(*) FROM Course.Session) AS sessions,
           (SELECT COUNT(*) FROM Course.Session WHERE StatusCode = 'CANCELED') AS canceled;"
