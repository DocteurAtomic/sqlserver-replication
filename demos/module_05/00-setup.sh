#!/usr/bin/env bash
# Module 5, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog (pull allowed), pushed to PachaCatalog on rpllab3. On rpllab3, the
# database of the reporting server, PachaReporting, is created empty with the schema Course
# (the snapshot creates tables, not schemas). On the shared volume, the folder m05/ receives the
# backups of clip 5.2.
# Usage: ./demos/module_05/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_05/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_05/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE PachaReporting;"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Course');
    SELECT DB_NAME() AS database_name, (SELECT COUNT(*) FROM sys.tables) AS tables, SCHEMA_ID(N'Course') AS schema_course;"
$engine exec -u 0 rpllab1 sh -c 'mkdir -p /var/opt/mssql/share/m05 && chown mssql:mssql /var/opt/mssql/share/m05'
echo "Backup folder /var/opt/mssql/share/m05 ready."
