#!/usr/bin/env bash
# Module 13, clip 13.3. The step skipped: the distributor is removed first, by force
# (sp_dropdistributor @no_checks = 1 on rpllab2), as when it is rebuilt or lost. One call drops the
# distribution database, the agent jobs, distributor_admin and the publisher registration; the
# publisher and the subscriber keep their replication: m13_Catalog published, the linked server
# repl_distributor, the subscriber registered, the subscription metadata on rpllab3. The usual
# calls then fail (18482: the distributor no longer knows the publisher); sp_removedbreplication
# removes the replication of an orphan database, sp_dropdistributor with @no_checks and
# @ignore_distributor the distributor of the publisher, sp_dropserver the subscriber. 00-setup.sh
# rebuilds the replication of the module first (about a minute).
# Usage: ./demos/module_13/04-orphan.sh     (with Podman: ENGINE=podman ./demos/module_13/04-orphan.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_13/lib.sh
refused() {  # instance, statement: a call expected to fail, shown with its message
    local n=$1 q=$2 out
    if out=$(sql $n -Q "SET NOCOUNT ON; $q" 2>&1); then echo "$out"; echo "expected a refusal: $q" >&2; exit 1; fi
    echo "$out" | grep -v '^$\|^Changed database context' | sed 's/, Line [0-9]*//'
}

./demos/module_13/00-setup.sh
echo "== rpllab2: the distributor removed first, by force"
sql rpllab2 -Q "SET NOCOUNT ON; EXEC sys.sp_dropdistributor @no_checks = 1;"
state
echo
echo "== rpllab1: the usual calls"
refused rpllab1 "USE m13_Catalog; EXEC sys.sp_dropsubscription @publication = N'm13_pubCatalog', @article = N'all', @subscriber = N'all';"
refused rpllab1 "EXEC sys.sp_dropdistributor;"
echo
echo "== sp_removedbreplication on the orphan databases"
sql rpllab1 -Q "SET NOCOUNT ON; EXEC sys.sp_removedbreplication @dbname = N'm13_Catalog', @type = N'both';"
sql rpllab3 -Q "SET NOCOUNT ON; EXEC sys.sp_removedbreplication @dbname = N'm13_Catalog';"
state
echo
echo "== rpllab1: the distributor without asking it, then the subscriber on both servers"
refused rpllab1 "EXEC sys.sp_dropdistributor;"
sql rpllab1 -Q "SET NOCOUNT ON; EXEC sys.sp_dropdistributor @no_checks = 1, @ignore_distributor = 1;"
for n in rpllab1 rpllab2; do
    sql $n -Q "SET NOCOUNT ON; EXEC sys.sp_dropserver @server = N'RPLLAB3', @droplogins = N'droplogins';"
done
./setup/repl-state.sh
