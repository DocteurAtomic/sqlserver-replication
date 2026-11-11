#!/usr/bin/env bash
# Module 6, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh, then gives PachadataTraining back as it was:
# the prices and statuses of the sessions saved by 00-setup.sh in m06_Work.dbo.SessionBefore,
# the sessions added by clip 6.1 deleted and the identity of Course.Session set back, the
# column added to Course.Course by clip 6.3 dropped and the one it widened set back to
# varchar(2000), the NOT FOR REPLICATION mark of the identity column of Course.Course removed,
# session 17622 set back to OPEN (the exercise cancels it) and the category EX of the exercise
# deleted. Replication is removed first, so that none of these changes travels to a
# subscriber. Last, it drops the databases the module and its exercise created: m06_Work on
# rpllab1; PachaCatalog, m06_Clause, m06_Immediate and ex_catalog on rpllab3; and checks that
# no replication is left.
# Usage: ./demos/module_06/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_06/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./setup/repl-remove.sh
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    IF OBJECT_ID(N'm06_Work.dbo.SessionBefore') IS NOT NULL
    BEGIN
        DECLARE @max int = (SELECT MAX(SessionId) FROM m06_Work.dbo.SessionBefore);
        UPDATE s SET Price = b.Price, StatusCode = b.StatusCode
        FROM Course.Session AS s JOIN m06_Work.dbo.SessionBefore AS b ON b.SessionId = s.SessionId
        WHERE s.Price IS DISTINCT FROM b.Price OR s.StatusCode IS DISTINCT FROM b.StatusCode;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' sessions set back');
        DELETE Course.Session WHERE SessionId > @max;
        PRINT CONCAT(N'rpllab1: ', @@ROWCOUNT, N' sessions added by the module deleted');
        DBCC CHECKIDENT (N'Course.Session', RESEED, @max) WITH NO_INFOMSGS;
    END;
    UPDATE Course.Session SET StatusCode = 'OPEN' WHERE SessionId = 17622 AND StatusCode = 'CANCELED';
    IF @@ROWCOUNT > 0 PRINT N'rpllab1: session 17622 of the exercise set back to OPEN';
    IF COL_LENGTH(N'Course.Course', N'WebSlug') IS NOT NULL
    BEGIN ALTER TABLE Course.Course DROP COLUMN WebSlug; PRINT N'rpllab1: column WebSlug dropped'; END;
    IF COL_LENGTH(N'Course.Course', N'PlanningComments') <> 2000
    BEGIN ALTER TABLE Course.Course ALTER COLUMN PlanningComments varchar(2000) NULL; PRINT N'rpllab1: PlanningComments set back to varchar(2000)'; END;
    IF EXISTS (SELECT * FROM sys.identity_columns WHERE object_id = OBJECT_ID(N'Course.Course') AND is_not_for_replication = 1)
    BEGIN
        DECLARE @o int = OBJECT_ID(N'Course.Course');
        EXEC sys.sp_identitycolumnforreplication @object_id = @o, @value = 0;
        PRINT N'rpllab1: NOT FOR REPLICATION removed from Course.Course';
    END;
    DELETE Course.Category WHERE CategoryCode = 'EX';
    IF @@ROWCOUNT > 0 PRINT N'rpllab1: category EX of the exercise deleted';"
sql rpllab1 -Q "SET NOCOUNT ON;
    IF DB_ID(N'm06_Work') IS NOT NULL
    BEGIN ALTER DATABASE m06_Work SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE m06_Work; END;"
sql rpllab3 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab3: database ' + name + N' dropped'';'
    FROM sys.databases WHERE name IN (N'PachaCatalog', N'm06_Clause', N'm06_Immediate', N'ex_catalog');
    EXEC (@q);"
./setup/repl-state.sh
