#!/usr/bin/env bash
# Exercise of module 7, starting state: the end of the exercise of module 4. Its own starting
# script removes what the demos (or anything else) left and builds the distributor and an empty
# ex_catalog; its solution publishes ex_pubCatalog (Course.Category, Course.Course,
# Course.Session), pushes it to ex_catalog, delivers the snapshot, inserts the category EX and
# posts a tracer token. Nothing of the exercise itself exists yet: no database ex_monitor, no job
# ex_agent_failure_watch, and the alert "Replication: agent failure" is disabled, as the
# distributor creates it.
# demos/module_07/99-cleanup.sh removes everything at the end, ex_monitor and the job included.
# Usage: ./exercises/module_07/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_07/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_07/99-cleanup.sh > /dev/null
./exercises/module_04/1-start.sh > /dev/null
sql rpllab3 < exercises/module_04/solution/1-schema.sql > /dev/null
sql rpllab1 < exercises/module_04/solution/2-publication.sql > /dev/null
./exercises/module_04/solution/3-deliver.sh > /dev/null
echo "ex_pubCatalog delivers Course.Category, Course.Course and Course.Session to ex_catalog on rpllab3."
