#!/usr/bin/env bash
# Module 4, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh, then gives the catalog of PachadataTraining
# back as it was: the prices saved by 00-setup.sh in m04_Journal.dbo.SessionBefore, the
# sessions added by clip 4.3 deleted and the identity of Course.Session set back, the category
# EX of the exercise deleted, the procedure of clip 4.4 dropped. Replication is removed first,
# so that none of these changes travels to a subscriber. Last, it drops the databases the module
# created: m04_Journal on rpllab1, PachaCatalog and ex_catalog on rpllab3, and checks that no
# replication is left.
# Usage: ./demos/module_04/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_04/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./setup/repl-remove.sh > /dev/null
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    IF OBJECT_ID(N'm04_Journal.dbo.SessionBefore') IS NOT NULL
    BEGIN
        DECLARE @max int = (SELECT MAX(SessionId) FROM m04_Journal.dbo.SessionBefore);
        UPDATE s SET Price = b.Price
        FROM Course.Session AS s JOIN m04_Journal.dbo.SessionBefore AS b ON b.SessionId = s.SessionId
        WHERE s.Price IS DISTINCT FROM b.Price;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' session prices set back');
        DELETE Course.Session WHERE SessionId > @max;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' sessions added by the module deleted');
        DBCC CHECKIDENT (N'Course.Session', RESEED, @max) WITH NO_INFOMSGS;
    END;
    DELETE Course.Category WHERE CategoryCode = 'EX';
    IF @@ROWCOUNT > 0 PRINT N'rpllab1: category EX of the exercise deleted';
    DROP PROCEDURE IF EXISTS Course.m04_RaiseSessionPrices;"
sql rpllab1 -Q "SET NOCOUNT ON;
    IF DB_ID(N'm04_Journal') IS NOT NULL
    BEGIN ALTER DATABASE m04_Journal SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE m04_Journal; END;"
sql rpllab3 -Q "SET NOCOUNT ON;
    IF DB_ID(N'PachaCatalog') IS NOT NULL
    BEGIN ALTER DATABASE PachaCatalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE PachaCatalog; END;
    IF DB_ID(N'ex_catalog') IS NOT NULL
    BEGIN ALTER DATABASE ex_catalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE ex_catalog; END;"
./setup/repl-state.sh
