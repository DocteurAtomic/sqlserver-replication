#!/usr/bin/env bash
# Exercise of module 2, starting state: the lab without any replication, as setup/install.sh
# leaves it. Removes what the demos of the module (or anything else) left, with
# setup/repl-remove.sh, which ends by checking that nothing is left.
# Usage: ./exercises/module_02/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_02/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
./setup/repl-remove.sh
