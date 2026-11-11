#!/usr/bin/env bash
# Module 7, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog, pushed to PachaCatalog on rpllab3. The demos of the module only read
# the state of the agents, stop and start them, take PachaCatalog offline for a while, and
# write net-zero changes to the prices of the sessions (+1 then -1 in the same transaction).
# Usage: ./demos/module_07/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_07/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_07/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
