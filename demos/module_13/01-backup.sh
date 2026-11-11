#!/usr/bin/env bash
# Module 13, clip 13.1. Backing up a topology. First what each role holds and must be backed up:
# the replication database of the role (publication, distribution, subscription) with master and
# msdb, their recovery model and their last full backup. Then the option sync with backup: on the
# distribution database, the log of the publication database is no longer truncated by its own
# log backup (log_reuse_wait_desc REPLICATION) until distribution itself is backed up; on the
# publication database, a transaction is not delivered until the log of the publication database
# is backed up ("Replicated transactions are waiting for next Log backup"). Needs 00-setup.sh.
# Usage: ./demos/module_13/01-backup.sh     (with Podman: ENGINE=podman ./demos/module_13/01-backup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_13/lib.sh

echo "== What each instance holds: the databases to back up"
for n in rpllab1 rpllab2 rpllab3; do
    sql $n -Q "SET NOCOUNT ON;
        SELECT @@SERVERNAME AS instance, d.name,
               CASE WHEN d.is_published = 1 THEN N'publication' WHEN d.is_distributor = 1 THEN N'distribution'
                    WHEN d.name IN (N'master', N'msdb') THEN N'system'
                    WHEN OBJECT_ID(QUOTENAME(d.name) + N'.dbo.MSreplication_subscriptions') IS NOT NULL THEN N'subscription'
                    ELSE N'' END AS role,
               d.recovery_model_desc AS recovery, d.is_subscribed,
               ISNULL(CONVERT(char(16), (SELECT MAX(b.backup_finish_date) FROM msdb.dbo.backupset b
                                         WHERE b.database_name = d.name AND b.type = 'D'), 120), N'never') AS last_full_backup
        FROM sys.databases d WHERE d.name NOT IN (N'tempdb', N'model', N'PachadataTraining') ORDER BY d.database_id;"
done

echo
echo "== sync with backup on the distribution database"
sql rpllab2 -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'distribution', @optname = N'sync with backup', @value = N'true';
    SELECT name, recovery_model_desc, DATABASEPROPERTYEX(name, 'IsSyncWithBackup') AS IsSyncWithBackup
    FROM sys.databases WHERE name = N'distribution';"
echo "-- rpllab1: 4 825 sessions changed, delivered, then a log backup of m13_Catalog"
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; UPDATE Course.Session SET Remarks = REPLICATE('a', 1000) WHERE SessionId % 4 = 0;"
s=$(date +%s)
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Session WHERE Remarks LIKE 'aaa%'" 4825 180
echo "rpllab3  4825 sessions changed, delivered in $(( $(date +%s) - s )) s"
sql rpllab1 -Q "SET NOCOUNT ON; BACKUP LOG m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-log.trn' WITH INIT;" | grep '^BACKUP'
logstate
echo "-- rpllab2: a full backup of distribution (simple recovery model)"
sql rpllab2 -Q "SET NOCOUNT ON; BACKUP DATABASE distribution TO DISK = N'/var/opt/mssql/share/m13_distribution-full.bak' WITH INIT, COMPRESSION;" | grep '^BACKUP'
echo "-- rpllab1: a log backup every 10 seconds until the log of m13_Catalog is released"
s=$(date +%s); i=0
while :; do
    i=$((i + 1))
    sql rpllab1 -Q "SET NOCOUNT ON; BACKUP LOG m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-log.trn' WITH INIT;" > /dev/null
    w=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT log_reuse_wait_desc FROM sys.databases WHERE name = N'm13_Catalog';" | tr -d '[:space:]')
    [ "$w" != REPLICATION ] && break
    if [ $(( $(date +%s) - s )) -gt 240 ]; then echo "the log of m13_Catalog was still held after 240 s" >&2; exit 1; fi
    sleep 10
done
echo "released after $i log backups, $(( $(date +%s) - s )) s after the backup of distribution"
logstate

echo
echo "== sync with backup on the publication database"
sql rpllab1 -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm13_Catalog', @optname = N'sync with backup', @value = N'true';
    SELECT name, DATABASEPROPERTYEX(name, 'IsSyncWithBackup') AS IsSyncWithBackup FROM sys.databases WHERE name = N'm13_Catalog';"
t=$(since)
sql rpllab1 -d m13_Catalog -Q "SET NOCOUNT ON; INSERT Course.Category (CategoryCode, Label, Description) VALUES ('M1', 'Module 13', 'sync with backup');"
echo "-- rpllab1: category M1 inserted at $(date -u +%T)"
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSlogreader_history WHERE time >= '$t' AND comments LIKE N'Replicated transactions are waiting%'" 1 150
lr_history "$t"
codes rpllab1; codes rpllab3
sql rpllab1 -Q "SET NOCOUNT ON; BACKUP LOG m13_Catalog TO DISK = N'/var/opt/mssql/share/m13_Catalog-log.trn' WITH INIT;" | grep '^BACKUP'
s=$(date +%s)
wait_for rpllab3 "SELECT COUNT(*) FROM m13_Catalog.Course.Category WHERE CategoryCode = 'M1'" 1 120
echo "-- rpllab3: M1 delivered $(( $(date +%s) - s )) s after the log backup"
lr_history "$t" | tail -1
codes rpllab3
