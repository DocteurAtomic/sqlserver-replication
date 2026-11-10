#!/usr/bin/env bash
# Removes all replication from the three instances, distributor first, then publisher, then
# subscriber, and checks with repl-state.sh that nothing is left. Used by the 99-cleanup of
# each module; it drops no database except distribution. The order and the reasons are in
# setup/repl-remove.sql.
# Usage: ./setup/repl-remove.sh     (with Podman: ENGINE=podman ./setup/repl-remove.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
for n in rpllab2 rpllab1 rpllab3; do
    # Jobs cannot be changed while the Agent is starting (Msg 14258), for instance just after
    # the instance started.
    wait_for $n "DECLARE @r int; EXEC @r = msdb.dbo.sp_is_sqlagent_starting; SELECT @r" 0 120
    sql $n -v N=$n < setup/repl-remove.sql
done
# Dropping the distribution database leaves the snapshot files on the shared volume.
$engine exec -u 0 rpllab1 sh -c 'rm -rf /var/opt/mssql/share/repldata/* && chown mssql:mssql /var/opt/mssql/share/repldata'
./setup/repl-state.sh
