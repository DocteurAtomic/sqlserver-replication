#!/usr/bin/env bash
# Module 13, clip 13.3. Removing replication in order, and reading after each step what is left on
# the three instances (demos/module_13/state.sql). Each call refused out of order is shown with
# its message: the publication while it has a subscription (14005), the distribution database
# while a publisher is registered (14120), the publisher registration while the publisher still
# uses this distributor (14098), the distributor while it has a distribution database (14121).
# With a remote distributor, the publisher drops its distributor (sp_dropdistributor) before the
# distributor drops the publisher (sp_dropdistpublisher). Last, the subscriber stays registered
# as a remote server on the publisher and on the distributor: sp_dropserver. The data of the
# subscriber stays. Needs 00-setup.sh (02-restore.sh may have run).
# Usage: ./demos/module_13/03-remove.sh     (with Podman: ENGINE=podman ./demos/module_13/03-remove.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_13/lib.sh
refused() {  # instance, statement: a call expected to fail, shown with its message
    local n=$1 q=$2 out
    if out=$(sql $n -Q "SET NOCOUNT ON; $q" 2>&1); then echo "$out"; echo "expected a refusal: $q" >&2; exit 1; fi
    echo "$out" | grep -v '^$\|^Changed database context' | sed 's/, Line [0-9]*//'
}

echo "== Before: the replication of m13_Catalog"
state
echo
echo "== Calls refused out of order"
refused rpllab1 "USE m13_Catalog; EXEC sys.sp_droppublication @publication = N'm13_pubCatalog';"
refused rpllab2 "EXEC sys.sp_dropdistributiondb @database = N'distribution';"
refused rpllab2 "EXEC sys.sp_dropdistributor;"

echo
echo "== 1. rpllab1: the subscriptions, the publication, then publishing on the database"
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropsubscription @publication = N'm13_pubCatalog', @article = N'all', @subscriber = N'all';
    EXEC sys.sp_droppublication @publication = N'm13_pubCatalog';
    EXEC sys.sp_replicationdboption @dbname = N'm13_Catalog', @optname = N'publish', @value = N'false';"
state
echo
echo "== 2. rpllab3: the subscription metadata of the push subscription"
sql rpllab3 -d m13_Catalog -Q "SET NOCOUNT ON;
    EXEC sys.sp_subscription_cleanup @publisher = N'rpllab1', @publisher_db = N'm13_Catalog', @publication = N'm13_pubCatalog';"
state | grep '^rpllab3:' || echo "rpllab3: nothing left"
echo
echo "== 3. rpllab2 first: refused while the publisher still uses this distributor"
refused rpllab2 "EXEC sys.sp_dropdistpublisher @publisher = N'rpllab1';"
echo "-- rpllab1: the distributor of the publisher"
sql rpllab1 -Q "SET NOCOUNT ON; EXEC sys.sp_dropdistributor;"
state | grep '^rpllab1:'
echo
echo "== 4. rpllab2: the publisher, the distribution database, the distributor"
sql rpllab2 -Q "SET NOCOUNT ON;
    EXEC sys.sp_dropdistpublisher @publisher = N'rpllab1';
    EXEC sys.sp_dropdistributiondb @database = N'distribution';
    EXEC sys.sp_dropdistributor;"
state
echo
echo "== 5. rpllab1 and rpllab2: the subscriber, still registered as a remote server"
for n in rpllab1 rpllab2; do
    sql $n -Q "SET NOCOUNT ON; EXEC sys.sp_dropserver @server = N'RPLLAB3', @droplogins = N'droplogins';"
done
state
./setup/repl-state.sh
sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'rpllab3  m13_Catalog kept: ', COUNT(*), N' sessions') FROM m13_Catalog.Course.Session;"
