#!/usr/bin/env bash
# Exercise of module 5, solution: a snapshot for the new subscription, delivered by the pull
# agent of rpllab3; then the category PL inserted on rpllab1 and a tracer token, both waited for
# at the subscriber.
# Usage: ./exercises/module_05/solution/2-deliver.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubCatalog';"
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM ex_pull.sys.partitions WHERE object_id = OBJECT_ID(N'ex_pull.Course.Session') AND index_id < 2), -1)" "$want" 180
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('PL', 'Pull', 'Category of the exercise of module 5');"
wait_for rpllab3 "SELECT COUNT(*) FROM ex_pull.Course.Category WHERE CategoryCode = 'PL'" 1 120
id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
    EXEC sys.sp_posttracertoken @publication = N'ex_pubCatalog', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE h.parent_tracer_id = $id AND a.subscriber_db = N'ex_pull' AND h.subscriber_commit IS NOT NULL" 1 120
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_helptracertokenhistory @publication = N'ex_pubCatalog', @tracer_id = $id;"
