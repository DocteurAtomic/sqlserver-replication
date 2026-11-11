#!/usr/bin/env bash
# Module 13, setup. 99-cleanup.sh first removes whatever a previous module or run left; then the
# distributor of the course (setup/repl-distributor.sh), and m13_Catalog: on rpllab3 an empty
# database with the schema Course, on rpllab1 a copy of the catalog of PachadataTraining with a
# first full backup, published by m13_pubCatalog and pushed to rpllab3 (00-catalog.sql). It waits
# until the snapshot is delivered. The backups and the restore of clip 13.1 are played on this
# copy, never on PachadataTraining.
# Usage: ./demos/module_13/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_13/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_13/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m13_Catalog;"
sql rpllab3 -d m13_Catalog -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Course');"
sql rpllab1 < demos/module_13/00-catalog.sql > /dev/null
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM m13_Catalog.sys.partitions WHERE object_id = OBJECT_ID(N'm13_Catalog.Course.Session') AND index_id < 2), -1)" 19300 180
echo "m13_pubCatalog delivered: 19300 sessions in m13_Catalog on rpllab3"
