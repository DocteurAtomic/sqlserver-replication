#!/usr/bin/env bash
# Exercise of module 3, starting state: the distributor of module 2 and nothing else. Removes
# what the demos of the module (or anything else) left with setup/repl-remove.sh, builds the
# distributor with setup/repl-distributor.sh, and creates the empty subscription database ex_ref
# on rpllab3 (dropped first if a previous attempt left it).
# Usage: ./exercises/module_03/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_03/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./setup/repl-remove.sh
./setup/repl-distributor.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON;
    IF DB_ID(N'ex_ref') IS NOT NULL
    BEGIN ALTER DATABASE ex_ref SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ex_ref; END;
    CREATE DATABASE ex_ref;"
echo "Distributor ready on rpllab2, empty database ex_ref on rpllab3."
