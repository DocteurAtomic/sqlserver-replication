#!/usr/bin/env bash
# Module 10, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog, pushed to PachaCatalog on rpllab3. Its three agents connect to the
# publisher and to the subscriber as sa, which is what the security audit of clip 10.1 refuses.
# Usage: ./demos/module_10/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_10/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_10/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
