#!/usr/bin/env bash
# Module 13, cleanup. Removes the replication of the module and of its exercise with
# setup/repl-remove.sh, then the databases the module created (m13_Catalog on rpllab1 and
# rpllab3, ex_catalog on rpllab3) and the backups of the module on the shared volume
# (/var/opt/mssql/share/m13_*). Last, it checks that no replication is left. Every error is
# shown: the output of repl-remove.sh is printed when it fails.
# Usage: ./demos/module_13/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_13/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
out=$(./setup/repl-remove.sh 2>&1) || { echo "$out" >&2; echo "99-cleanup: setup/repl-remove.sh failed" >&2; exit 1; }
for n in rpllab1 rpllab3; do
    sql $n -Q "SET NOCOUNT ON;
        DECLARE @q nvarchar(max) = N'';
        SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                     + QUOTENAME(name) + N'; PRINT N''$n: database ' + name + N' dropped'';'
        FROM sys.databases WHERE name IN (N'm13_Catalog', N'ex_catalog');
        EXEC (@q);"
done
$engine exec -u 0 rpllab1 sh -c 'rm -f /var/opt/mssql/share/m13_*'
./setup/repl-state.sh
