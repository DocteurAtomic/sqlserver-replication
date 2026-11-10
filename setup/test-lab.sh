#!/usr/bin/env bash
# Checks that the three instances answer as setup/install.sh leaves them: names, version,
# Agent running, 2 GB, snapshot folder, PachadataTraining on rpllab1. Prints one line per
# check and exits with 1 when one check fails or one instance does not answer.
# It does not look at replication: setup/repl-state.sh does.
# Usage: ./setup/test-lab.sh     (with Podman: ENGINE=podman ./setup/test-lab.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
fail=0
for n in $nodes; do
    out=$(sql $n -h -1 -v N=$n < setup/test-lab.sql 2>&1)
    if [ $? -ne 0 ] || [ -z "$out" ]; then
        echo "FAIL $n: does not answer"; echo "$out" | head -3; fail=1; continue
    fi
    echo "$out"
    echo "$out" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The lab is not in the expected state."; exit 1; fi
echo "The lab is ready."
