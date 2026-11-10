#!/usr/bin/env bash
# Module 2, clip 2.1. The names replication works with. Each container has a hostname
# (compose.yaml), which is the @@SERVERNAME of its instance, and the instances find each other
# by that name on the network rpllab-net. Then, on rpllab2, sp_adddistributor is given
# "localhost", then the IP address of rpllab2, instead of its name: the procedure takes any
# name other than @@SERVERNAME for a remote distributor, connects to it through the linked
# server repl_distributor, finds rpllab2 itself at the other end, and fails with Msg 18483.
# The certificate is trusted in both calls, so that the error shown is the one about the name
# and not the one about the certificate (clip 2.3). The script checks that both calls fail
# with 18483, then drops the linked server they leave behind: the lab is as it was.
# Usage: ./demos/module_02/01-server-names.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh

echo "== Server names and the names the network resolves"
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$n: @@SERVERNAME = ', @@SERVERNAME, N', MachineName = ', CAST(SERVERPROPERTY('MachineName') AS sysname));"
done
echo "-- seen from rpllab1:"
$engine exec rpllab1 getent hosts rpllab2 rpllab3 | sort -u

ip=$($engine exec rpllab1 getent hosts rpllab2 | awk 'NR == 1 {print $1}')
for name in localhost "$ip"; do
    echo
    echo "== rpllab2: sp_adddistributor @distributor = N'$name'"
    out=$(sql rpllab2 -Q "EXEC sys.sp_adddistributor @distributor = N'$name', @password = N'Dist-2026!lab', @trust_distributor_certificate = N'yes';" 2>&1) && {
        echo "$out"; echo "Unexpected: '$name' was accepted as the name of the distributor." >&2; exit 1; }
    echo "$out"
    echo "$out" | grep -q 'Msg 18483' || { echo "Unexpected error, Msg 18483 expected." >&2; exit 1; }
    sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'left on rpllab2: linked server ', name, N', data source ', data_source) FROM sys.servers WHERE name = N'repl_distributor';"
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.sp_get_distributor;"
    sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.sp_dropserver @server = N'repl_distributor', @droplogins = 'droplogins';"
done
echo
./setup/repl-state.sh
