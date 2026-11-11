#!/usr/bin/env bash
# Module 13, clip 13.1. Restoring the publisher, on the same instance and under the same name,
# which keeps the replication settings (is_published stays 1, without KEEP_REPLICATION).
# First without sync with backup on m13_Catalog: category R1, written after the full backup, is
# delivered, then lost by the restore on the publisher and kept by the subscriber; the Log Reader
# Agent fails on a system assertion (3624, with a memory dump on rpllab1) because the distribution
# database is ahead of the restored log; sp_replrestart resynchronizes them, and what was written
# between the restore and sp_replrestart (R2) is never delivered. Then with sync with backup: S2,
# written after the last log backup, is never delivered, and lost on both sides by the restore of
# the full backup and of that log backup; the agent goes on without sp_replrestart. The dump files
# that the assertion writes in /var/opt/mssql/log of rpllab1 are deleted at the end of the scene.
# Needs 00-setup.sh and 01-backup.sh.
# Usage: ./demos/module_13/02-restore.sh     (with Podman: ENGINE=podman ./demos/module_13/02-restore.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_13/lib.sh
restore() {  # restore m13_Catalog on rpllab1 from the backups given (full, then logs)
    local q="ALTER DATABASE m13_Catalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE;" f last=${@: -1}
    for f in "$@"; do
        case $f in
            *.bak) q+=" RESTORE DATABASE m13_Catalog FROM DISK = N'/var/opt/mssql/share/$f' WITH REPLACE, $( [ "$f" = "$last" ] && echo RECOVERY || echo NORECOVERY );" ;;
            *.trn) q+=" RESTORE LOG m13_Catalog FROM DISK = N'/var/opt/mssql/share/$f' WITH $( [ "$f" = "$last" ] && echo RECOVERY || echo NORECOVERY );" ;;
        esac
    done
    q+=" ALTER DATABASE m13_Catalog SET MULTI_USER;"
    sql rpllab1 -Q "SET NOCOUNT ON; $q" | grep '^RESTORE'
    sql rpllab1 -Q "SET NOCOUNT ON; SELECT name, is_published, DATABASEPROPERTYEX(name, 'IsSyncWithBackup') AS IsSyncWithBackup
        FROM sys.databases WHERE name = N'm13_Catalog';"
}
dumps() { $engine exec rpllab1 sh -c 'ls /var/opt/mssql/log | grep "^SQLDump" || true'; }

echo "== Without sync with backup on m13_Catalog"
sql rpllab1 -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm13_Catalog', @optname = N'sync with backup', @value = N'false';
    BACKUP DATABASE m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-A.bak' WITH INIT, COMPRESSION;" | grep '^BACKUP'
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('R1', 'Restore', 'after the full backup');"
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Category WHERE CategoryCode = 'R1'" 1 120
echo "-- R1 written after the full backup, delivered"
codes rpllab1; codes rpllab3
before=$(dumps)
t=$(since)
echo "-- rpllab1: restore of the full backup"
restore m13_Catalog-A.bak
codes rpllab1; codes rpllab3
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSlogreader_history WHERE time >= '$t' AND runstatus = 6 AND comments LIKE N'%sp_repldone%'" 1 150
stop_job $logreader
echo "-- rpllab2: the Log Reader Agent after the restore (job stopped)"
lr_history "$t"
errors "$t"
echo "-- rpllab1: the error log"
$engine exec rpllab1 sh -c 'grep -a "Failed Assertion" /var/opt/mssql/log/errorlog | tail -1 | cut -c1-200'
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('R2', 'Restore', 'before sp_replrestart');"
echo "-- rpllab1: R2 written, then sp_replrestart and the agent started again"
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; EXEC sys.sp_replrestart;"
t=$(since)
start_job $logreader
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('R3', 'Restore', 'after sp_replrestart');"
s=$(date +%s)
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Category WHERE CategoryCode = 'R3'" 1 120
echo "-- R3 delivered in $(( $(date +%s) - s )) s"
codes rpllab1; codes rpllab3
new=$(comm -13 <(echo "$before") <(dumps) | sed '/^$/d')
echo "-- rpllab1: $(echo "$new" | grep -c . || true) dump files written by the assertion, deleted"
for f in $new; do $engine exec -u 0 rpllab1 rm -f "/var/opt/mssql/log/$f"; done

echo
echo "== With sync with backup on m13_Catalog"
sql rpllab1 -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm13_Catalog', @optname = N'sync with backup', @value = N'true';
    BACKUP DATABASE m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-B.bak' WITH INIT, COMPRESSION;" | grep '^BACKUP'
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('S1', 'Sync', 'in the log backup');
    BACKUP LOG m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-B1.trn' WITH INIT;" | grep '^BACKUP'
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Category WHERE CategoryCode = 'S1'" 1 120
t=$(since)
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('S2', 'Sync', 'after the last log backup');"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSlogreader_history WHERE time >= '$t' AND comments LIKE N'Replicated transactions are waiting%'" 1 150
echo "-- S1 in the log backup, delivered; S2 after it, waiting"
lr_history "$t"
codes rpllab1; codes rpllab3
echo "-- rpllab1: restore of the full backup and of the log backup"
restore m13_Catalog-B.bak m13_Catalog-B1.trn
codes rpllab1; codes rpllab3
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('S3', 'Sync', 'after the restore');
    BACKUP LOG m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-B2.trn' WITH INIT;" | grep '^BACKUP'
s=$(date +%s)
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Category WHERE CategoryCode = 'S3'" 1 180
echo "-- S3 written and backed up after the restore, delivered in $(( $(date +%s) - s )) s, without sp_replrestart"
lr_history "$t" | tail -4
codes rpllab1; codes rpllab3
