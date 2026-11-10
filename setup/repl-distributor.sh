#!/usr/bin/env bash
# Builds the distributor of the course: distribution database on rpllab2, rpllab1 registered
# as its publisher, snapshot folder /var/opt/mssql/share/repldata. The state module 2 ends with,
# that the 00-setup of later modules starts from.
# Usage: ./setup/repl-distributor.sh     (with Podman: ENGINE=podman ./setup/repl-distributor.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
sql rpllab2 -v STEP=dist < setup/repl-distributor.sql > /dev/null
sql rpllab1 -v STEP=pub < setup/repl-distributor.sql > /dev/null
sql rpllab1 -h -1 -Q "SET NOCOUNT ON; EXEC sys.sp_get_distributor;" | head -1
