#!/usr/bin/env bash
# Builds the replication of the catalog, the state module 4 ends with: the distributor (if it
# is missing), the subscription database PachaCatalog on rpllab3 with the schema Course (the
# Distribution Agent does not create schemas), publication pubCatalog and its push
# subscription, then waits until the snapshot is delivered.
# Usage: ./setup/repl-catalog.sh     (with Podman: ENGINE=podman ./setup/repl-catalog.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
if [ "$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; DECLARE @d TABLE (i int, s sysname NULL, a int, b int, c int); INSERT @d EXEC sys.sp_get_distributor; SELECT i FROM @d;" | tr -d '[:space:]')" != 1 ]; then
    ./setup/repl-distributor.sh > /dev/null
fi
sql rpllab3 -Q "IF DB_ID(N'PachaCatalog') IS NULL CREATE DATABASE PachaCatalog;" > /dev/null
sql rpllab3 -d PachaCatalog -Q "IF SCHEMA_ID(N'Course') IS NULL EXEC (N'CREATE SCHEMA Course');" > /dev/null
sql rpllab1 < setup/repl-catalog.sql > /dev/null
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM PachaCatalog.sys.partitions WHERE object_id = OBJECT_ID(N'PachaCatalog.Course.Session') AND index_id < 2), -1)" "$want" 180
echo "pubCatalog delivered: $want sessions on rpllab3"
