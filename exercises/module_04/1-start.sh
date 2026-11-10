#!/usr/bin/env bash
# Exercise of module 4, starting state: the distributor of module 2 and nothing else.
# demos/module_04/99-cleanup.sh removes what the demos of the module (or anything else) left and
# gives the catalog of PachadataTraining back as it was, the category EX of a previous attempt
# included; setup/repl-distributor.sh builds the distributor; on rpllab3, the subscription
# database ex_catalog is created empty.
# Usage: ./exercises/module_04/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_04/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_04/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE ex_catalog;"
echo "Distributor ready on rpllab2, empty database ex_catalog on rpllab3."
