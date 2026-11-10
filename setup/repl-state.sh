#!/usr/bin/env bash
# Lists what replication leaves on the three instances: distribution database, published and
# subscribed databases, the repl_distributor server, replication jobs, the login
# distributor_admin, the publishers registered at the distributor. Exits with 0 and says so
# when there is none, which is the state setup/install.sh leaves, and with 1 otherwise.
# Usage: ./setup/repl-state.sh     (with Podman: ENGINE=podman ./setup/repl-state.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
left=0
for n in $nodes; do
    out=$(sql $n -h -1 -v N=$n < setup/repl-state.sql 2>&1) || { echo "FAIL $n: $out"; exit 1; }
    if [ -n "$out" ]; then echo "$out"; left=1; fi
done
if [ $left -ne 0 ]; then echo "Replication is still configured."; exit 1; fi
echo "No replication on the three instances."
