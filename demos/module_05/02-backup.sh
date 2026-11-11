#!/usr/bin/env bash
# Module 5, clip 5.2. Enrollment.Enrollment (151 236 rows) for the reporting server, initialized
# from a backup of PachadataTraining instead of a snapshot. A snapshot publication refuses the
# option (Msg 18787). Publication m05_pubEnrollment allows initialization from a backup, with
# @immediate_sync true as Learn asks; its article has manual identity range management, which
# adds 0x04 to its schema options: the update procedure it generates does not set the identity
# column, and the Distribution Agent can create it on the restored table, where the column kept
# its IDENTITY property (with the default schema options, Msg 8102). The
# backup, an enrollment written after it, the restore on rpllab3 as m05_Enrollment and the
# tables that are not published dropped there. Then the subscription: three wrong calls
# (Msg 14043 without the device name, 3206 when the device type is left to its default,
# logical, 21397 with a backup taken before the publication), the right one, and the
# enrollment written after the backup found at the subscriber. Last, for comparison, a
# snapshot of the same table delivered to an empty database, m05_Snapshot.
# Needs 01-pull.sh first (or 00-setup.sh: the clip does not use the pull subscription).
# Usage: ./demos/module_05/02-backup.sh     (with Podman: ENGINE=podman ./demos/module_05/02-backup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
dir=/var/opt/mssql/share/m05
rows() {  # instance, database: rows and checksum of Enrollment.Enrollment, and the rows of the module
    sql $1 -d $2 -Q "SET NOCOUNT ON;
        SELECT N'$1' AS instance, COUNT(*) AS rows, CHECKSUM_AGG(BINARY_CHECKSUM(*)) AS checksum,
               SUM(IIF(OrderReference LIKE 'M05-%', 1, 0)) AS rows_of_the_module
        FROM Enrollment.Enrollment;"
}

echo "== rpllab1: a snapshot publication and the option"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_addpublication @publication = N'm05_pubSnap', @repl_freq = N'snapshot',
     @status = N'active', @allow_initialize_from_backup = N'true';" 2>&1 | filter || true

echo
echo "== rpllab1: a backup taken before the publication exists"
sql rpllab1 -Q "SET NOCOUNT ON; BACKUP DATABASE PachadataTraining TO DISK = N'$dir/before-publication.bak' WITH COMPRESSION, INIT;" | tail -1

echo
echo "== rpllab1: publication m05_pubEnrollment"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'm05_pubEnrollment', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'true', @allow_initialize_from_backup = N'true';
    -- Manual identity range management adds 0x04 to the schema options (0x30077): the identity
    -- column keeps its IDENTITY property, and the update procedure does not set it.
    EXEC sys.sp_addarticle @publication = N'm05_pubEnrollment', @article = N'Enrollment',
         @source_owner = N'Enrollment', @source_object = N'Enrollment', @identityrangemanagementoption = N'manual';
    SELECT name, status, immediate_sync, allow_initialize_from_backup, sync_method FROM dbo.syspublications
    WHERE name = N'm05_pubEnrollment';
    SELECT a.name AS article, a.status, CONVERT(varchar(18), a.schema_option, 1) AS schema_option
    FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid WHERE p.name = N'm05_pubEnrollment';
    SELECT name AS identity_column, is_not_for_replication FROM sys.identity_columns
    WHERE object_id = OBJECT_ID(N'Enrollment.Enrollment');" 2>&1 | filter

echo
echo "== rpllab1: the backup, then an enrollment written after it"
t0=$(date +%s%N)
sql rpllab1 -Q "SET NOCOUNT ON; BACKUP DATABASE PachadataTraining TO DISK = N'$dir/PachadataTraining.bak' WITH COMPRESSION, INIT;" | tail -1
echo "backup: $(( ($(date +%s%N) - t0) / 1000000 )) ms seen from the host"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Enrollment.Enrollment (SessionId, ContactId, Discount, Attended, CreationDate, OrderReference,
                                  AgreementSent, JoiningInstructionsSent, WaitingList)
    VALUES (18061, 52368, 0, 0, '20261111', 'M05-AFTER-BACKUP', 0, 0, 0);
    SELECT EnrollmentId, SessionId, OrderReference FROM Enrollment.Enrollment WHERE OrderReference = 'M05-AFTER-BACKUP';"
$engine exec rpllab1 ls -l $dir

echo
echo "== rpllab3: the restore, as m05_Enrollment"
t0=$(date +%s%N)
sql rpllab3 -Q "SET NOCOUNT ON; RESTORE DATABASE m05_Enrollment FROM DISK = N'$dir/PachadataTraining.bak'
    WITH MOVE N'PachadataTraining' TO N'/var/opt/mssql/data/m05_Enrollment.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/m05_Enrollment_log.ldf';" | tail -1
echo "restore: $(( ($(date +%s%N) - t0) / 1000000 )) ms seen from the host"
sql rpllab3 -d m05_Enrollment -Q "SET NOCOUNT ON;
    SELECT DB_NAME() AS database_name, (SELECT COUNT(*) FROM sys.tables) AS tables,
           (SELECT COUNT(*) FROM sys.tables WHERE is_published = 1) AS published_tables,
           (SELECT COUNT(*) FROM Enrollment.Enrollment WHERE OrderReference = 'M05-AFTER-BACKUP') AS row_after_backup;"
echo "-- rpllab3: what the reporting server does not want, dropped"
sql rpllab3 -d m05_Enrollment -Q "SET NOCOUNT ON;
    ALTER DATABASE m05_Enrollment SET RECOVERY SIMPLE;
    DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'ALTER TABLE ' + QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id)) + N'.'
                 + QUOTENAME(OBJECT_NAME(parent_object_id)) + N' DROP CONSTRAINT ' + QUOTENAME(name) + N';'
    FROM sys.foreign_keys;
    EXEC (@q);
    SET @q = N'';
    SELECT @q += N'DROP TABLE ' + QUOTENAME(SCHEMA_NAME(schema_id)) + N'.' + QUOTENAME(name) + N';'
    FROM sys.tables WHERE NOT (SCHEMA_NAME(schema_id) = N'Enrollment' AND name = N'Enrollment');
    EXEC (@q);
    SELECT (SELECT COUNT(*) FROM sys.tables) AS tables, (SELECT COUNT(*) FROM sys.foreign_keys) AS foreign_keys,
           (SELECT COUNT(*) FROM sys.views) AS views, (SELECT COUNT(*) FROM sys.procedures) AS procedures,
           (SELECT COUNT(*) FROM Enrollment.Enrollment) AS enrollments;"

echo
echo "== rpllab1: the subscription, three wrong calls first"
add="EXEC sys.sp_addsubscription @publication = N'm05_pubEnrollment', @subscriber = N'rpllab3',
     @destination_db = N'm05_Enrollment', @subscription_type = N'push', @sync_type = N'initialize with backup', @article = N'all'"
echo "-- without the backup"
sql rpllab1 -d PachadataTraining -Q "$add;" 2>&1 | filter || true
echo "-- the file, with the default device type"
sql rpllab1 -d PachadataTraining -Q "$add, @backupdevicename = N'$dir/PachadataTraining.bak';" 2>&1 | filter || true
echo "-- the backup taken before the publication"
sql rpllab1 -d PachadataTraining -Q "$add, @backupdevicetype = N'disk', @backupdevicename = N'$dir/before-publication.bak';" 2>&1 | filter || true
echo "-- the backup of the publication"
t0=$(date +%s%N)
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; $add, @backupdevicetype = N'disk', @backupdevicename = N'$dir/PachadataTraining.bak';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm05_pubEnrollment', @subscriber = N'rpllab3',
         @subscriber_db = N'm05_Enrollment', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;" 2>&1 | filter
wait_for rpllab3 "SELECT COUNT(*) FROM m05_Enrollment.Enrollment.Enrollment WHERE OrderReference = 'M05-AFTER-BACKUP'" 1 150
echo "subscription to the enrollment at the subscriber: $(( ($(date +%s%N) - t0) / 1000000 )) ms seen from the host"
echo "-- rpllab2: the history of the agent"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, LEFT(h.comments, 150) AS comments
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'm05_Enrollment' ORDER BY h.timestamp;
    SELECT subscriber_db, sync_type, status FROM dbo.MSsubscriptions WHERE subscriber_db = N'm05_Enrollment';"
echo "-- rpllab1 and rpllab3: the same rows"
rows rpllab1 PachadataTraining
rows rpllab3 m05_Enrollment
echo "-- rpllab3: what the agent created"
sql rpllab3 -d m05_Enrollment -Q "SET NOCOUNT ON;
    SELECT name FROM sys.procedures WHERE name LIKE N'sp_MS%' ORDER BY name;
    SELECT publisher, publication, subscription_type FROM dbo.MSreplication_subscriptions;"

echo
echo "== The same table by a snapshot, into an empty database"
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m05_Snapshot;"
sql rpllab3 -d m05_Snapshot -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Enrollment');"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication_snapshot @publication = N'm05_pubEnrollment', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addsubscription @publication = N'm05_pubEnrollment', @subscriber = N'rpllab3',
         @destination_db = N'm05_Snapshot', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm05_pubEnrollment', @subscriber = N'rpllab3',
         @subscriber_db = N'm05_Snapshot', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;" 2>&1 | filter
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Enrollment.Enrollment" | tr -d '[:space:]')
t0=$(date +%s%N)
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'm05_pubEnrollment';"
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM m05_Snapshot.sys.partitions WHERE object_id = OBJECT_ID(N'm05_Snapshot.Enrollment.Enrollment') AND index_id < 2), -1)" "$want" 150
echo "snapshot started to rows at the subscriber: $(( ($(date +%s%N) - t0) / 1000000 )) ms seen from the host"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT N'snapshot agent' AS agent, CONVERT(char(23), MIN(h.time), 121) AS first_line, CONVERT(char(23), MAX(h.time), 121) AS last_line,
           DATEDIFF(millisecond, MIN(h.time), MAX(h.time)) AS ms
    FROM dbo.MSsnapshot_history h JOIN dbo.MSsnapshot_agents a ON a.id = h.agent_id WHERE a.publication = N'm05_pubEnrollment';
    SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, LEFT(h.comments, 150) AS comments
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'm05_Snapshot' AND h.comments LIKE N'Delivered snapshot%';"
rows rpllab3 m05_Snapshot
