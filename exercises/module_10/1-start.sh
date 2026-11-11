#!/usr/bin/env bash
# Exercise of module 10, starting state: the publication of the exercise of module 4, its agents
# connected as sa. demos/module_10/99-cleanup.sh removes what the demos (or anything else) left;
# setup/repl-distributor.sh builds the distributor; on rpllab3, ex_catalog is created with the
# schema Course; then the solution of the exercise of module 4 publishes the catalog of
# PachadataTraining (ex_pubCatalog) to ex_catalog and delivers the snapshot. The category EX is
# added to Course.Category; check.sh changes its description to see a change arrive. Last, the
# login ex_reporting of a reporting tool, with a user in PachadataTraining, is added to the PAL
# of ex_pubCatalog, where the audit does not want it. About a minute.
# demos/module_10/99-cleanup.sh removes everything at the end, the logins ex_ included.
# Usage: ./exercises/module_10/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_10/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_10/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE ex_catalog;"
sql rpllab3 < exercises/module_04/solution/1-schema.sql > /dev/null
sql rpllab1 < exercises/module_04/solution/2-publication.sql > /dev/null
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('EX', 'Exercise', 'Category of the exercise of module 10');
    EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubCatalog';" > /dev/null
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM ex_catalog.sys.partitions WHERE object_id = OBJECT_ID(N'ex_catalog.Course.Session') AND index_id < 2), -1)" "$want" 180
wait_for rpllab3 "SELECT COUNT(*) FROM ex_catalog.Course.Category WHERE CategoryCode = 'EX'" 1 120
# A login enters the PAL only if it exists on the distributor too (Msg 21048), with the same
# password.
sql rpllab2 -Q "SET NOCOUNT ON; CREATE LOGIN ex_reporting WITH PASSWORD = N'Reporting-2026!ex', CHECK_POLICY = OFF;" > /dev/null
sql rpllab1 -Q "SET NOCOUNT ON;
    CREATE LOGIN ex_reporting WITH PASSWORD = N'Reporting-2026!ex', CHECK_POLICY = OFF;
    USE PachadataTraining; CREATE USER ex_reporting FOR LOGIN ex_reporting;
    EXEC sys.sp_grant_publication_access @publication = N'ex_pubCatalog', @login = N'ex_reporting';" > /dev/null
echo "ex_pubCatalog delivered to ex_catalog on rpllab3; its agents connect as sa; ex_reporting is in its PAL."
