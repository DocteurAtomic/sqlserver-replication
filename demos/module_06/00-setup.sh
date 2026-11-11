#!/usr/bin/env bash
# Module 6, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog, pushed to PachaCatalog on rpllab3. On rpllab1, the database of the
# module, m06_Work, keeps the price and the status of every session (dbo.SessionBefore), read by
# 99-cleanup.sh to undo the changes of the demos. On rpllab3, two empty databases with the
# schema Course for the publications of the module: m06_Clause (clip 6.1) and m06_Immediate
# (clip 6.2).
# Usage: ./demos/module_06/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_06/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_06/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE m06_Work;"
sql rpllab1 -d m06_Work -Q "SET NOCOUNT ON;
    SELECT SessionId, Price, StatusCode INTO dbo.SessionBefore FROM PachadataTraining.Course.Session;
    SELECT COUNT(*) AS sessions_saved, MAX(SessionId) AS last_session,
           SUM(IIF(StatusCode = 'CANCELED', 1, 0)) AS canceled FROM dbo.SessionBefore;"
for d in m06_Clause m06_Immediate; do
    sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE $d;"
    sql rpllab3 -d $d -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Course');"
done
sql rpllab3 -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name IN (N'PachaCatalog', N'm06_Clause', N'm06_Immediate') ORDER BY name;"
