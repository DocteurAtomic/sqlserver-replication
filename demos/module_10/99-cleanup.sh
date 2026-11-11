#!/usr/bin/env bash
# Module 10, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh: the database master key of distribution, and
# the certificate and key replication created under it, go with the distribution database.
# Then, on each instance, the proxies and credentials that a @job_login left for the agents of
# PachadataTraining (clip 10.1), the users the module and the exercise created in
# PachadataTraining, and their logins (m10_ and ex_ prefixes); the categories MS (clip 10.1)
# and EX (exercise) of PachadataTraining; the databases PachaCatalog, m10_Reporting and
# ex_catalog on rpllab3, the master key of m10_Reporting with it. The rights of the snapshot
# folder are set back (clip 10.2 makes it read-only). The two containers of
# 04-certificate.sh are removed if a run stopped before its end. Last, it checks that no
# replication is left. Every error is shown.
# Usage: ./demos/module_10/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_10/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
# The output of repl-remove.sh is kept and shown when it fails: a silent failure here left the
# CI of module 7 red with nothing to read (11 November 2026).
out=$(./setup/repl-remove.sh 2>&1) || { echo "$out" >&2; echo "99-cleanup: setup/repl-remove.sh failed" >&2; exit 1; }
for n in rpllab1 rpllab2 rpllab3; do
    sql $n -Q "SET NOCOUNT ON;
        DECLARE @q nvarchar(max) = N'';
        -- A @job_login gives the job step a proxy and a credential named [REPL][<login>][<job>].
        SELECT @q += N'EXEC msdb.dbo.sp_delete_proxy @proxy_name = N''' + REPLACE(name, N'''', N'''''') + N'''; PRINT N''$n: proxy '
                     + REPLACE(name, N'''', N'''''') + N' dropped'';'
        FROM msdb.dbo.sysproxies WHERE name LIKE N'[[]REPL]%[[]RPLLAB1-PachadataTraining-%' OR name LIKE N'[[]REPL]%[[]RPLLAB1-PachadataTraining-ex[_]%';
        SELECT @q += N'DROP CREDENTIAL ' + QUOTENAME(name) + N'; PRINT N''$n: credential dropped'';'
        FROM sys.credentials WHERE name LIKE N'[[]REPL]%[[]RPLLAB1-PachadataTraining-%' OR name LIKE N'[[]REPL]%[[]RPLLAB1-PachadataTraining-ex[_]%';
        IF DB_ID(N'PachadataTraining') IS NOT NULL
            SELECT @q += N'USE PachadataTraining; DROP USER ' + QUOTENAME(name) + N'; PRINT N''$n: user ' + name + N' dropped'';'
            FROM PachadataTraining.sys.database_principals WHERE type = 'S' AND (name LIKE N'm10[_]%' OR name LIKE N'ex[_]%');
        -- Sessions of a login are closed before the login is dropped.
        SELECT @q += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions
        WHERE login_name LIKE N'm10[_]%' OR login_name LIKE N'ex[_]%';
        SELECT @q += N'DROP LOGIN ' + QUOTENAME(name) + N'; PRINT N''$n: login ' + name + N' dropped'';'
        FROM sys.server_principals WHERE type = 'S' AND (name LIKE N'm10[_]%' OR name LIKE N'ex[_]%');
        EXEC (@q);"
done
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DELETE Course.Category WHERE CategoryCode IN ('MS', 'EX');
    IF @@ROWCOUNT > 0 PRINT N'rpllab1: categories MS and EX deleted';"
sql rpllab3 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab3: database ' + name + N' dropped'';'
    FROM sys.databases WHERE name IN (N'PachaCatalog', N'm10_Reporting', N'ex_catalog');
    EXEC (@q);"
$engine exec -u 0 rpllab1 sh -c 'chmod -R u+rwX,go+rX /var/opt/mssql/share/repldata && chown -R mssql:mssql /var/opt/mssql/share/repldata'
for c in m10tls1 m10tls2; do
    if $engine inspect $c > /dev/null 2>&1; then
        $engine rm -f $c > /dev/null && echo "container $c removed"
    fi
done
if $engine network inspect m10tls-net > /dev/null 2>&1; then $engine network rm m10tls-net > /dev/null && echo "network m10tls-net removed"; fi
./setup/repl-state.sh
