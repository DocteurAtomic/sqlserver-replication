#!/usr/bin/env bash
# Module 2, setup. The module starts from the lab as setup/install.sh leaves it: three instances,
# PachadataTraining on rpllab1, no replication anywhere. When a previous module or run left
# some, it is removed (setup/repl-remove.sh), then the lab is checked (setup/test-lab.sh).
# Usage: ./demos/module_02/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_02/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
if ! ./setup/repl-state.sh >/dev/null; then
    ./setup/repl-remove.sh
fi
./setup/test-lab.sh
./setup/repl-state.sh
