#!/usr/bin/env bash
# Module 10, clip 10.3. Encryption and secrets. First the connections of the agents: not
# encrypted by default, encrypted with -EncryptionLevel 1 on the command of the Distribution
# Agent, refused with -EncryptionLevel 2 (Agent message code 20084), the certificates of the
# lab being self-signed; the command set back. Then the passwords of the agents in the
# distribution database: without a database master key, the same header and eight bytes more
# per character, and the warning of SQL Server 2025 at each procedure. CREATE MASTER KEY in
# distribution, then each secret written again by the procedure that owns it: the certificate
# and the symmetric key SQLSERVER_REPLICATION appear, every password gets the same new header
# and a length rounded to the block, the agents restarted connect, and the master key cannot be
# dropped any more. Last, the secret of the pull subscription of 02-pal.sh, in the
# subscription database, with its own master key.
# Needs 00-setup.sh, 01-accounts.sh and 02-pal.sh first.
# Usage: ./demos/module_10/03-secrets.sh     (with Podman: ENGINE=podman ./demos/module_10/03-secrets.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_10/lib.sh
connections() {  # the connections of the push Distribution Agent of PachaCatalog, encrypted or not (not the pull one of 02-pal.sh)
    for n in rpllab2 rpllab3; do
        sql $n -h -1 -Q "SET NOCOUNT ON;
            SELECT CONCAT(N'$n  ', s.login_name, N'  encrypt_option ', c.encrypt_option)
            FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
            WHERE s.program_name IN (N'$distrib', N'rpllab1_PachadataTraining_pubCatalog')
              AND (N'$n' = N'rpllab2' OR DB_NAME(s.database_id) = N'PachaCatalog') ORDER BY s.session_id;"
    done | sed '/^$/d'
}
level() {  # -EncryptionLevel on the command of the Distribution Agent: a value, or nothing to remove it
    sql rpllab2 -Q "SET NOCOUNT ON;
        DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                                    WHERE j.name = N'$distrib' AND js.step_id = 2);
        SET @c = RTRIM(LEFT(@c, CHARINDEX(N' -EncryptionLevel', @c + N' -EncryptionLevel') - 1)) + IIF(N'$1' = N'', N'', N' -EncryptionLevel $1');
        EXEC msdb.dbo.sp_update_jobstep @job_name = N'$distrib', @step_id = 2, @command = @c;
        SELECT RIGHT(js.command, 40) AS end_of_command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
        WHERE j.name = N'$distrib' AND js.step_id = 2;"
}
secrets() {  # the stored passwords of the agents: length and first sixteen bytes
    sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
        SELECT N'Log Reader' AS agent, publisher_login AS login, DATALENGTH(publisher_password) AS bytes,
               CONVERT(varchar(34), CAST(publisher_password AS varbinary(16)), 1) AS first_bytes FROM dbo.MSlogreader_agents
        UNION ALL SELECT N'Snapshot', publisher_login, DATALENGTH(publisher_password), CONVERT(varchar(34), CAST(publisher_password AS varbinary(16)), 1)
        FROM dbo.MSsnapshot_agents
        UNION ALL SELECT N'Distribution, push', subscriber_login, DATALENGTH(subscriber_password), CONVERT(varchar(34), CAST(subscriber_password AS varbinary(16)), 1)
        FROM dbo.MSdistribution_agents WHERE subscription_type = 0
        UNION ALL SELECT N'publisher registration', login, DATALENGTH(password), CONVERT(varchar(34), CAST(password AS varbinary(16)), 1)
        FROM msdb.dbo.MSdistpublishers;"
}

echo "== The connections of the Distribution Agent, by default"
connections
echo "-- rpllab2: -EncryptionLevel 1"
level 1
restart_job $distrib
wait_for rpllab3 "SELECT COUNT(*) FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
                  WHERE s.program_name = N'rpllab1_PachadataTraining_pubCatalog' AND c.encrypt_option = 'TRUE'" 2 120
connections
echo "-- rpllab2: -EncryptionLevel 2"
level 2
h=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT MAX(instance_id) FROM msdb.dbo.sysjobhistory;" | tr -d '[:space:]')
restart_job $distrib
wait_for rpllab2 "SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
                  WHERE j.name = N'$distrib' AND h.instance_id > $h AND h.message LIKE N'%Agent message code%'" 1 120
sql rpllab2 -h -1 -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.message INTO #m FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'$distrib' AND h.instance_id > $h AND h.message LIKE N'%Agent message code%' ORDER BY h.instance_id DESC;
    SELECT LTRIM(REPLACE(value, CHAR(13), N'')) FROM #m CROSS APPLY STRING_SPLIT(message, CHAR(10))
    WHERE value LIKE N'%EncryptionLevel%' OR value LIKE N'%Connecting%' OR value LIKE N'%message code%';" | sed '/^$/d'
connections
echo "-- rpllab2: the command set back"
level ""
restart_job $distrib
wait_for rpllab3 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM sys.dm_exec_sessions WHERE login_name = N'm10_distrib'" 1 120
connections

echo
echo "== rpllab2: the secrets of the agents, without a database master key"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT name, is_master_key_encrypted_by_server FROM sys.databases WHERE name = N'distribution';
    SELECT COUNT(*) AS keys_in_distribution FROM distribution.sys.symmetric_keys;"
secrets
echo "-- rpllab1: a change of password, as clip 10.1 made them"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0,
         @publisher_login = N'm10_logreader', @publisher_password = N'LogReader-2026!m10';"

echo
echo "== rpllab2: a database master key in distribution"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'DistKey-2026!m10';
    SELECT name, is_master_key_encrypted_by_server FROM sys.databases WHERE name = N'distribution';"
secrets
echo "-- each secret written again by its procedure"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0,
         @publisher_login = N'm10_logreader', @publisher_password = N'LogReader-2026!m10';
    EXEC sys.sp_changepublication_snapshot @publication = N'pubCatalog', @publisher_security_mode = 0,
         @publisher_login = N'm10_snapshot', @publisher_password = N'Snapshot-2026!m10';
    EXEC sys.sp_changesubscription @publication = N'pubCatalog', @article = N'all', @subscriber = N'rpllab3',
         @destination_db = N'PachaCatalog', @property = N'subscriber_password', @value = N'Distrib-2026!m10';"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    EXEC sys.sp_changedistpublisher @publisher = N'rpllab1', @property = N'password', @value = N'Repl-2026!lab';"
secrets
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT name, key_algorithm FROM sys.symmetric_keys ORDER BY name;
    SELECT name, pvt_key_encryption_type_desc, CONVERT(char(10), start_date, 120) AS start_date, CONVERT(char(10), expiry_date, 120) AS expiry_date
    FROM sys.certificates;"
echo "-- the agents restarted"
restart_job $logreader
restart_job $distrib
wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%' AND login_name = N'm10_logreader'" 1 90
wait_for rpllab3 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM sys.dm_exec_sessions WHERE login_name = N'm10_distrib'" 1 90
agent_logins
t=$(since)
start_job $snapshot
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history WHERE time >= '$t' AND runstatus IN (2, 6)" 1 90
history snapshot "$t" | tail -1
echo "-- rpllab2: the master key, now in use"
sql rpllab2 -d distribution -Q "DROP MASTER KEY;" || true

echo
echo "== rpllab3: the secret of the pull subscription, in m10_Reporting"
q="SELECT distributor_login, DATALENGTH(distributor_password) AS bytes, CONVERT(varchar(34), CAST(distributor_password AS varbinary(16)), 1) AS first_bytes
   FROM dbo.MSsubscription_properties;"
sql rpllab3 -d m10_Reporting -Q "SET NOCOUNT ON; $q"
sql rpllab3 -d m10_Reporting -Q "SET NOCOUNT ON; CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'SubKey-2026!m10';
    EXEC sys.sp_change_subscription_properties @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @property = N'distributor_password', @value = N'Pull-2026!m10';
    $q
    SELECT name FROM sys.symmetric_keys ORDER BY name;"
