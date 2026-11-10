#!/usr/bin/env bash
# Exercise of module 2: checks the distributor asked for. It reads the state of the two
# instances, never a script. On rpllab2: the distributor installed, a distribution database
# named ex_distribution, in the simple recovery model, keeping transactions 48 hours at most
# and history 96 hours (sp_helpdistributiondb), rpllab1 registered as its publisher with the
# snapshot folder /var/opt/mssql/share/repldata (msdb.dbo.MSdistpublishers). On rpllab1: the
# distributor registered (sp_get_distributor), the linked server repl_distributor marked as
# distributor and pointing to rpllab2.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_02/check.sh     (with Podman: ENGINE=podman ./exercises/module_02/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
out2=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
DECLARE @d TABLE (installed int, distribution_server sysname NULL, distribution_db_installed int,
                  is_distribution_publisher int, has_remote_distribution_publisher int);
INSERT @d EXEC sys.sp_get_distributor;
INSERT @r SELECT IIF(installed = 1 AND UPPER(distribution_server) = N'RPLLAB2', 1, 0),
    N'rpllab2 is installed as its own distributor (sp_adddistributor on rpllab2)' FROM @d;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.databases WHERE name = N'ex_distribution' AND is_distributor = 1), 1, 0),
    N'a distribution database named ex_distribution (sp_adddistributiondb)';
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.databases WHERE name = N'ex_distribution' AND recovery_model_desc = N'SIMPLE'), 1, 0),
    N'ex_distribution in the simple recovery model';
IF OBJECT_ID(N'msdb.dbo.MSdistributiondbs') IS NULL
    INSERT @r VALUES (0, N'transactions kept 48 hours at most in ex_distribution: no distribution database'),
                     (0, N'agent history kept 96 hours in ex_distribution: no distribution database');
ELSE
BEGIN
-- The retention sp_helpdistributiondb shows is read in msdb.dbo.MSdistributiondbs, where it
-- is stored: sp_helpdistributiondb cannot be called inside INSERT ... EXEC (Msg 8164).
INSERT @r SELECT ISNULL(MAX(IIF(max_distretention = 48, 1, 0)), 0),
    CONCAT(N'transactions kept 48 hours at most in ex_distribution (max_distretention is ',
           ISNULL(CAST(MAX(max_distretention) AS nvarchar(10)), N'unknown'), N')')
FROM msdb.dbo.MSdistributiondbs WHERE name = N'ex_distribution';
INSERT @r SELECT ISNULL(MAX(IIF(history_retention = 96, 1, 0)), 0),
    CONCAT(N'agent history kept 96 hours in ex_distribution (history_retention is ',
           ISNULL(CAST(MAX(history_retention) AS nvarchar(10)), N'unknown'), N')')
FROM msdb.dbo.MSdistributiondbs WHERE name = N'ex_distribution';
END;
IF OBJECT_ID(N'msdb.dbo.MSdistpublishers') IS NOT NULL
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.MSdistpublishers WHERE UPPER(name) = N'RPLLAB1'
                                 AND distribution_db = N'ex_distribution'
                                 AND working_directory = N'/var/opt/mssql/share/repldata'), 1, 0),
        N'rpllab1 registered at the distributor, with ex_distribution and the snapshot folder /var/opt/mssql/share/repldata (sp_adddistpublisher)';
ELSE
    INSERT @r SELECT 0, N'rpllab1 registered at the distributor (sp_adddistpublisher): no publisher registered';
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
out1=$(sql rpllab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
DECLARE @d TABLE (installed int, distribution_server sysname NULL, distribution_db_installed int,
                  is_distribution_publisher int, has_remote_distribution_publisher int);
INSERT @d EXEC sys.sp_get_distributor;
INSERT @r SELECT IIF(installed = 1 AND UPPER(distribution_server) = N'RPLLAB2', 1, 0),
    CONCAT(N'rpllab1 knows rpllab2 as its distributor (sp_adddistributor on rpllab1; distribution server is ',
           ISNULL(distribution_server, N'none'), N')') FROM @d;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.servers WHERE name = N'repl_distributor' AND is_distributor = 1
                             AND UPPER(data_source) = N'RPLLAB2'), 1, 0),
    N'the linked server repl_distributor of rpllab1 is marked as distributor and points to rpllab2';
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
# Six checks on rpllab2, two on rpllab1: a missing line or an error message is a failure,
# so that a check that did not run is never taken for a check that passed.
fail=0
for pair in "6:$out2" "2:$out1"; do
    want=${pair%%:*}; o=${pair#*:}
    echo "$o"
    got=$(echo "$o" | grep -cE '^(OK|FAIL) ')
    if [ "$got" -ne "$want" ] || echo "$o" | grep -q '^Msg '; then
        echo "FAIL $got checks out of $want ran on this instance"; fail=1
    fi
    echo "$o" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The distributor of the exercise is not complete."; exit 1; fi
echo "rpllab2 is the distributor of rpllab1, with ex_distribution kept 48 hours and its history 96 hours."
