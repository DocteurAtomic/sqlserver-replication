#!/usr/bin/env bash
# Module 3, setup. The module starts from the distributor of module 2: any replication left by a
# previous module or run is removed (setup/repl-remove.sh), then setup/repl-distributor.sh builds
# the distributor on rpllab2 with rpllab1 as its publisher. On rpllab3, the database of the
# finance department, PachaReporting, is created empty: no schema Reference, on purpose (clip 3.3).
# Usage: ./demos/module_03/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_03/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
if ! ./setup/repl-state.sh >/dev/null; then
    ./setup/repl-remove.sh
fi
./setup/repl-distributor.sh
sql rpllab3 -Q "SET NOCOUNT ON;
    IF DB_ID(N'PachaReporting') IS NOT NULL
    BEGIN
        ALTER DATABASE PachaReporting SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE PachaReporting;
    END;
    CREATE DATABASE PachaReporting;
    SELECT name, recovery_model_desc FROM sys.databases WHERE name = N'PachaReporting';"
