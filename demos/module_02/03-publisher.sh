#!/usr/bin/env bash
# Module 2, clip 2.3. rpllab1 registers rpllab2 as its distributor. SQL Server 2025 connects to
# a remote distributor through OLE DB provider 19, which encrypts and checks the certificate:
# the self-signed certificate of rpllab2 is refused (HResult 0x80090301 under Linux), and the
# failed call leaves the linked server repl_distributor behind. The second call trusts the
# certificate (@trust_distributor_certificate = N'yes', as setup/repl-distributor.sql does),
# and rpllab1 is a publisher of rpllab2: the state module 2 ends with, and that the following
# modules start from. Needs 02-distribution-db.sql first.
# Usage: ./demos/module_02/03-publisher.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
show() {  # what rpllab1 knows of its distributor
    sql rpllab1 -Q "SET NOCOUNT ON;
        SELECT name, data_source, provider_string, is_distributor FROM sys.servers WHERE name = N'repl_distributor';
        EXEC sys.sp_get_distributor;"
}

echo "== rpllab1: sp_adddistributor @distributor = N'rpllab2'"
out=$(sql rpllab1 -Q "EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab';" 2>&1) && {
    echo "$out"; echo "Unexpected: the certificate of rpllab2 was accepted." >&2; exit 1; }
echo "$out"
echo "$out" | grep -q 'SSL Provider' || { echo "Unexpected error, an SSL Provider error expected." >&2; exit 1; }
show

echo
echo "== rpllab1: the same call, trusting the certificate"
sql rpllab1 -Q "EXEC sys.sp_adddistributor @distributor = N'rpllab2', @password = N'Dist-2026!lab', @trust_distributor_certificate = N'yes';"
show
sql rpllab1 -Q "SET NOCOUNT ON; EXEC sys.sp_helpdistributor;"
# The properties sp_changedistributor_property can change on the publisher; after an upgrade
# to SQL Server 2025, trust_distributor_certificate is the one that brings a remote
# distributor back (module 13).
sql rpllab1 -Q "SET NOCOUNT ON; EXEC sys.sp_changedistributor_property;"
