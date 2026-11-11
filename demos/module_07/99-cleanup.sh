#!/usr/bin/env bash
# Module 7, cleanup. Brings PachaCatalog and ex_catalog back online if a demo or check.sh was
# stopped while they were offline, removes the publications, subscriptions and the distributor
# of the module and of its exercise with setup/repl-remove.sh (the replication alerts and the
# thresholds go with the distributor), then removes what the module added outside replication:
# on rpllab2, the login m07_monitor of clip 7.1, the job ex_agent_failure_watch and the database
# ex_monitor of the exercise; on rpllab1, the categories EX (exercise 4, replayed by the start of
# the exercise) and X7 (written by check.sh); on rpllab3, PachaCatalog and ex_catalog. Last, it
# checks that no replication is left.
# Usage: ./demos/module_07/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_07/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
sql rpllab3 -Q "SET NOCOUNT ON;
    IF DATABASEPROPERTYEX(N'PachaCatalog', N'Status') = N'OFFLINE' ALTER DATABASE PachaCatalog SET ONLINE;
    IF DATABASEPROPERTYEX(N'ex_catalog', N'Status') = N'OFFLINE' ALTER DATABASE ex_catalog SET ONLINE;"
./setup/repl-remove.sh > /dev/null
sql rpllab2 -Q "SET NOCOUNT ON;
    IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'ex_agent_failure_watch')
    BEGIN EXEC msdb.dbo.sp_delete_job @job_name = N'ex_agent_failure_watch'; PRINT N'rpllab2: job ex_agent_failure_watch dropped'; END;
    IF DB_ID(N'ex_monitor') IS NOT NULL
    BEGIN ALTER DATABASE ex_monitor SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ex_monitor; PRINT N'rpllab2: database ex_monitor dropped'; END;
    IF SUSER_ID(N'm07_monitor') IS NOT NULL
    BEGIN DROP LOGIN m07_monitor; PRINT N'rpllab2: login m07_monitor dropped'; END;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DELETE Course.Category WHERE CategoryCode IN ('EX', 'X7');
    DECLARE @n int = @@ROWCOUNT;
    IF @n > 0 PRINT CONCAT(N'rpllab1: ', @n, N' categories of the exercises deleted');"
sql rpllab3 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab3: database ' + name + N' dropped'';'
    FROM sys.databases WHERE name IN (N'PachaCatalog', N'ex_catalog');
    EXEC (@q);"
./setup/repl-state.sh
