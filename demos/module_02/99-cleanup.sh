#!/usr/bin/env bash
# Module 2, cleanup. Removes the distributor built by the demos or by the exercise (any
# distribution database, ex_distribution included), and the registration of rpllab1, with
# setup/repl-remove.sh, which ends by checking that no replication is left. The module
# creates no other database.
# Usage: ./demos/module_02/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_02/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
./setup/repl-remove.sh
