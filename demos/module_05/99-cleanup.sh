#!/usr/bin/env bash
# Module 5, cleanup. Removes the publications, subscriptions and the distributor of the module
# and of its exercise with setup/repl-remove.sh, pull subscriptions included, then gives
# PachadataTraining back as it was: the enrollments written by clip 5.2 (OrderReference
# starting with M05-) and the categories of the exercises (EX of module 4, PL of module 5)
# deleted, the identity of Enrollment.Enrollment set back. Replication is removed first, so that
# none of these changes travels to a subscriber. Last, it drops the databases the module and
# its exercise created on rpllab3 (PachaCatalog, PachaReporting, m05_Enrollment, m05_Snapshot,
# ex_catalog, ex_pull) and the backups of clip 5.2 on the shared volume, and checks that no
# replication is left.
# Usage: ./demos/module_05/99-cleanup.sh     (with Podman: ENGINE=podman ./demos/module_05/99-cleanup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./setup/repl-remove.sh
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    DELETE Enrollment.Enrollment WHERE OrderReference LIKE 'M05-%';
    IF @@ROWCOUNT > 0
    BEGIN
        PRINT N'rpllab1: enrollments of the module deleted';
        DECLARE @max int = (SELECT MAX(EnrollmentId) FROM Enrollment.Enrollment);
        DBCC CHECKIDENT (N'Enrollment.Enrollment', RESEED, @max) WITH NO_INFOMSGS;
    END;
    DELETE Course.Category WHERE CategoryCode IN ('EX', 'PL');
    IF @@ROWCOUNT > 0 PRINT N'rpllab1: categories of the exercises deleted';"
sql rpllab3 -Q "SET NOCOUNT ON;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER DATABASE ' + QUOTENAME(name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE '
                 + QUOTENAME(name) + N'; PRINT N''rpllab3: database ' + name + N' dropped'';'
    FROM sys.databases
    WHERE name IN (N'PachaCatalog', N'PachaReporting', N'm05_Enrollment', N'm05_Snapshot', N'ex_catalog', N'ex_pull');
    EXEC (@q);"
$engine exec -u 0 rpllab1 rm -rf /var/opt/mssql/share/m05
./setup/repl-state.sh
