#!/usr/bin/env bash
# Exercise of module 4, solution: the initial snapshot, then a change and a tracer token.
# Starts the Snapshot Agent of ex_pubCatalog and waits until the Distribution Agent has delivered
# the snapshot to ex_catalog; inserts the category EX on rpllab1 and waits for it on rpllab3;
# posts a tracer token and waits until it has reached the subscriber, then prints its latency.
# Usage: ./exercises/module_04/solution/3-deliver.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubCatalog';"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.subscriber_db = N'ex_catalog' AND h.comments LIKE N'Delivered snapshot%'" 1 180
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('EX', 'Exercise', 'Category of the exercise of module 4');"
wait_for rpllab3 "SELECT COUNT(*) FROM ex_catalog.Course.Category WHERE CategoryCode = 'EX'" 1 120
id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
    EXEC sys.sp_posttracertoken @publication = N'ex_pubCatalog', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history WHERE parent_tracer_id = $id AND subscriber_commit IS NOT NULL" 1 120
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_helptracertokenhistory @publication = N'ex_pubCatalog', @tracer_id = $id;"
