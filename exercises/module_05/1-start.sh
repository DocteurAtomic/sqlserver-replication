#!/usr/bin/env bash
# Exercise of module 5, starting state: the end of the exercise of module 4. Its own starting
# script removes what the demos (or anything else) left and builds the distributor and an empty
# ex_catalog; its solution publishes ex_pubCatalog (pull allowed), pushes it to ex_catalog,
# delivers the snapshot, inserts the category EX and posts a tracer token. On rpllab3, the
# database of the exercise, ex_pull, is created empty.
# demos/module_05/99-cleanup.sh removes everything at the end, ex_pull and the categories included.
# Usage: ./exercises/module_05/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_05/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_05/99-cleanup.sh > /dev/null
./exercises/module_04/1-start.sh > /dev/null
sql rpllab3 < exercises/module_04/solution/1-schema.sql > /dev/null
sql rpllab1 < exercises/module_04/solution/2-publication.sql > /dev/null
./exercises/module_04/solution/3-deliver.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE ex_pull;"
echo "ex_pubCatalog delivers the catalog to ex_catalog (push); empty database ex_pull on rpllab3."
