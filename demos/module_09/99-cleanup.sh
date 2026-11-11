#!/usr/bin/env bash
# Module 9, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh; the agent profiles the module and the exercise
# created live in msdb of rpllab2 and go with the distributor (sp_dropdistributor deletes the
# rows of msdb.dbo.MSagent_profiles, user profiles included, checked by this script). Then it
# drops the databases the module created: m09_Billing and ex_billing on rpllab1, m09_Billing,
# ex_billing and PachaCatalog on rpllab3, and checks that no replication is left.
# PachadataTraining is only read by the module: nothing to give back.
# Usage: ./demos/module_09/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_09/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
# The output of repl-remove.sh is kept and shown when it fails: a silent failure here left the
# CI of module 7 red with nothing to read (11 November 2026).
out=$(./setup/repl-remove.sh 2>&1) || { echo "$out" >&2; echo "99-cleanup: setup/repl-remove.sh failed" >&2; exit 1; }
left=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; IF OBJECT_ID(N'msdb.dbo.MSagent_profiles') IS NULL SELECT 0;
    ELSE EXEC (N'SELECT COUNT(*) FROM msdb.dbo.MSagent_profiles WHERE type = 1;');" | tr -d '[:space:]')
if [ "$left" != 0 ]; then echo "rpllab2: $left user agent profile(s) left in msdb after the distributor was dropped" >&2; exit 1; fi
for n in rpllab1 rpllab3; do
    sql $n -Q "SET NOCOUNT ON;
        DECLARE @q nvarchar(max) = N'';
        SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                     + QUOTENAME(name) + N'; PRINT N''$n: database ' + name + N' dropped'';'
        FROM sys.databases WHERE name IN (N'm09_Billing', N'ex_billing', N'PachaCatalog');
        EXEC (@q);"
done
./setup/repl-state.sh
