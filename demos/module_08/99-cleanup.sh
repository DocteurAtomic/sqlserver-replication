#!/usr/bin/env bash
# Module 8, cleanup. Sets the retention of the distribution database back to 72 hours if clip
# 8.4 was stopped before the end, then removes the publications, subscriptions and the
# distributor of the module and of its exercise with setup/repl-remove.sh (agent profiles and
# job steps go with the distributor). Replication is removed first, so that none of the next
# changes travels to a subscriber. Then it gives PachadataTraining back as it was: the prices
# saved by 00-setup.sh in m08_Journal.dbo.SessionBefore, and by the exercise in
# ex_incident.dbo.SessionBefore; the categories Z8 (clip 8.2), EX (exercise 4, replayed by the
# start of the exercise), X1 and X3 (the failures of the exercise) deleted. Last, it drops the
# databases the module created: m08_Journal and ex_incident on rpllab1 (and the backup files
# of m08_Journal), m08_Journal, m08_Enrollment, PachaCatalog and ex_catalog on rpllab3, and
# checks that no replication is left.
# Usage: ./demos/module_08/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_08/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
# The retention of clip 8.4 set back to 72, when a distributor is there (none in the start state)
sql rpllab2 -Q "SET NOCOUNT ON;
    IF OBJECT_ID(N'msdb.dbo.MSdistributiondbs') IS NOT NULL
        EXEC (N'IF EXISTS (SELECT * FROM msdb.dbo.MSdistributiondbs WHERE name = N''distribution'' AND max_distretention <> 72)
            EXEC sys.sp_changedistributiondb @database = N''distribution'', @property = N''max_distretention'', @value = N''72'';');" > /dev/null
./setup/repl-remove.sh > /dev/null
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    IF OBJECT_ID(N'm08_Journal.dbo.SessionBefore') IS NOT NULL
    BEGIN
        UPDATE s SET Price = b.Price
        FROM Course.Session AS s JOIN m08_Journal.dbo.SessionBefore AS b ON b.SessionId = s.SessionId
        WHERE s.Price IS DISTINCT FROM b.Price;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' session prices set back (demos)');
    END;
    IF OBJECT_ID(N'ex_incident.dbo.SessionBefore') IS NOT NULL
    BEGIN
        UPDATE s SET Price = b.Price
        FROM Course.Session AS s JOIN ex_incident.dbo.SessionBefore AS b ON b.SessionId = s.SessionId
        WHERE s.Price IS DISTINCT FROM b.Price;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' session prices set back (exercise)');
    END;
    DELETE Course.Category WHERE CategoryCode IN ('Z8', 'EX', 'X1', 'X3');
    DECLARE @n int = @@ROWCOUNT;
    IF @n > 0 PRINT CONCAT(N'rpllab1: ', @n, N' categories of the module deleted');"
sql rpllab1 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab1: database ' + name + N' dropped'';'
    FROM sys.databases WHERE name IN (N'm08_Journal', N'ex_incident');
    EXEC (@q);"
$engine exec rpllab1 rm -f /var/opt/mssql/data/m08_Journal.bak /var/opt/mssql/data/m08_Journal.trn
sql rpllab3 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab3: database ' + name + N' dropped'';'
    FROM sys.databases WHERE name IN (N'm08_Journal', N'm08_Enrollment', N'PachaCatalog', N'ex_catalog');
    EXEC (@q);"
./setup/repl-state.sh
