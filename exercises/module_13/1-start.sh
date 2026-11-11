#!/usr/bin/env bash
# Exercise of module 13, starting state: the replication of the exercise of module 4, to remove.
# demos/module_13/99-cleanup.sh removes what the demos (or anything else) left;
# setup/repl-distributor.sh builds the distributor; on rpllab3, ex_catalog is created with the
# schema Course; then the solution of the exercise of module 4 publishes the catalog of
# PachadataTraining (ex_pubCatalog) to ex_catalog, and its snapshot is run and delivered. About a minute.
# demos/module_13/99-cleanup.sh removes everything at the end, ex_catalog included.
# Usage: ./exercises/module_13/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_13/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_13/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE ex_catalog;"
sql rpllab3 < exercises/module_04/solution/1-schema.sql > /dev/null
sql rpllab1 < exercises/module_04/solution/2-publication.sql > /dev/null
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubCatalog';" > /dev/null
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM ex_catalog.sys.partitions WHERE object_id = OBJECT_ID(N'ex_catalog.Course.Session') AND index_id < 2), -1)" "$want" 180
echo "ex_pubCatalog delivered to ex_catalog on rpllab3: $want sessions. Remove this replication."
