#!/usr/bin/env bash
# Module 3, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh, which ends by checking that no replication is
# left, then drops the subscription databases the module created on rpllab3 (PachaReporting,
# ex_ref of the exercise).
# Usage: ./demos/module_03/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_03/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./setup/repl-remove.sh
sql rpllab3 -Q "SET NOCOUNT ON;
    IF DB_ID(N'PachaReporting') IS NOT NULL
    BEGIN ALTER DATABASE PachaReporting SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE PachaReporting; END;
    IF DB_ID(N'ex_ref') IS NOT NULL
    BEGIN ALTER DATABASE ex_ref SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ex_ref; END;"
