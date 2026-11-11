#!/usr/bin/env bash
# Module 10, clip 10.1. The accounts of the agents. First who the three agents of pubCatalog
# are connected as: sa on the publisher and on the subscriber, the SQL Server Agent service
# account (NT AUTHORITY\NETWORK SERVICE, sysadmin) on the distributor, which a push agent
# cannot change under Linux. Then each agent gets a dedicated SQL Server login, and each right
# is measured refused, then granted: the Log Reader Agent (m10_logreader, db_owner of
# PachadataTraining on rpllab1), the Snapshot Agent (m10_snapshot, the same), the Distribution
# Agent (m10_distrib, db_owner of PachaCatalog on rpllab3). The new login is taken when the
# agent starts again, not before. Last, two traps: a sp_changelogreader_agent without the
# password empties it, and a @job_login gives the job a proxy that cannot run under Linux.
# Needs 00-setup.sh first.
# Usage: ./demos/module_10/01-accounts.sh     (with Podman: ENGINE=podman ./demos/module_10/01-accounts.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_10/lib.sh

echo "== Who the agents of pubCatalog are connected as"
agent_logins
echo "-- rpllab2: the account of the agents on the distributor, and their jobs"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT name, IS_SRVROLEMEMBER(N'sysadmin', name) AS is_sysadmin FROM sys.server_principals
    WHERE name = N'NT AUTHORITY\NETWORK SERVICE';
    SELECT j.name AS job, SUSER_SNAME(j.owner_sid) AS owner, js.subsystem, js.proxy_id
    FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps js ON js.job_id = j.job_id
    WHERE j.name IN (N'$logreader', N'$snapshot', N'$distrib') AND js.step_id = 2 ORDER BY j.name;
    SELECT SUBSTRING(js.command, CHARINDEX(N'-DistributorSecurityMode', js.command), 26) AS distributor_connection
    FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id WHERE j.name = N'$distrib' AND js.step_id = 2;"

echo
echo "== The Log Reader Agent: a login without any right"
sql rpllab1 -Q "SET NOCOUNT ON;
    CREATE LOGIN m10_logreader WITH PASSWORD = N'LogReader-2026!m10', CHECK_POLICY = OFF;
    USE PachadataTraining; CREATE USER m10_logreader FOR LOGIN m10_logreader;
    EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0,
         @publisher_login = N'm10_logreader', @publisher_password = N'LogReader-2026!m10';" 2>&1 | filter
sql rpllab2 -d distribution -Q "SET NOCOUNT ON; SELECT name, publisher_security_mode, publisher_login FROM dbo.MSlogreader_agents;"
echo "-- the agent still runs as before"
agent_logins | grep LogReader
t=$(since)
restart_job $logreader
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSlogreader_history WHERE time >= '$t' AND runstatus = 6" 1 90
echo "-- rpllab2: restarted"
history logreader "$t"
echo "-- rpllab1: db_owner of PachadataTraining"
sql rpllab1 -d PachadataTraining -Q "ALTER ROLE db_owner ADD MEMBER m10_logreader;"
# The job retries every minute: the next attempt connects.
wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%' AND login_name = N'm10_logreader'" 1 150
history logreader "$t" | tail -3
agent_logins | grep LogReader

echo
echo "== The Snapshot Agent"
sql rpllab1 -Q "SET NOCOUNT ON;
    CREATE LOGIN m10_snapshot WITH PASSWORD = N'Snapshot-2026!m10', CHECK_POLICY = OFF;
    USE PachadataTraining; CREATE USER m10_snapshot FOR LOGIN m10_snapshot;
    EXEC sys.sp_changepublication_snapshot @publication = N'pubCatalog', @publisher_security_mode = 0,
         @publisher_login = N'm10_snapshot', @publisher_password = N'Snapshot-2026!m10';" 2>&1 | filter
t=$(since)
start_job $snapshot
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history WHERE time >= '$t' AND runstatus IN (2, 6)" 1 90
history snapshot "$t" | grep -v "Azure Storage"
sql rpllab1 -d PachadataTraining -Q "ALTER ROLE db_owner ADD MEMBER m10_snapshot;"
wait_for rpllab2 "$(running $snapshot)" 0 60
t=$(since)
start_job $snapshot
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history WHERE time >= '$t' AND runstatus IN (2, 6)" 1 90
echo "-- rpllab1: db_owner, run again"
history snapshot "$t" | grep -v "Azure Storage"

echo
echo "== The Distribution Agent: its connection to the subscriber"
sql rpllab3 -Q "SET NOCOUNT ON;
    CREATE LOGIN m10_distrib WITH PASSWORD = N'Distrib-2026!m10', CHECK_POLICY = OFF;
    USE PachaCatalog; CREATE USER m10_distrib FOR LOGIN m10_distrib;" | filter
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changesubscription @publication = N'pubCatalog', @article = N'all', @subscriber = N'rpllab3',
         @destination_db = N'PachaCatalog', @property = N'subscriber_login', @value = N'm10_distrib';" 2>&1 | filter
echo "-- rpllab2: after the login alone"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT subscriber_login, DATALENGTH(subscriber_password) AS password_bytes FROM dbo.MSdistribution_agents WHERE name = N'$distrib';"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changesubscription @publication = N'pubCatalog', @article = N'all', @subscriber = N'rpllab3',
         @destination_db = N'PachaCatalog', @property = N'subscriber_password', @value = N'Distrib-2026!m10';" 2>&1 | filter
echo "-- rpllab2: after the password"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT subscriber_login, DATALENGTH(subscriber_password) AS password_bytes FROM dbo.MSdistribution_agents WHERE name = N'$distrib';"
t=$(since)
restart_job $distrib
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.name = N'$distrib' AND h.time >= '$t' AND h.runstatus = 6" 1 90
history $distrib "$t"
echo "-- rpllab3: db_owner of PachaCatalog"
sql rpllab3 -d PachaCatalog -Q "ALTER ROLE db_owner ADD MEMBER m10_distrib;"
wait_for rpllab3 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM sys.dm_exec_sessions WHERE login_name = N'm10_distrib'" 1 150
agent_logins | grep -v LogReader
echo "-- rpllab1: a change, and its arrival on rpllab3"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    INSERT Course.Category (CategoryCode, Label, Description) VALUES ('MS', 'Security audit', 'Category of module 10');"
wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Category WHERE CategoryCode = 'MS'" 1 60
sql rpllab3 -Q "SET NOCOUNT ON;
    SELECT CategoryCode, Label FROM PachaCatalog.Course.Category WHERE CategoryCode = 'MS';
    EXECUTE AS LOGIN = N'm10_distrib';
    SELECT HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW SERVER PERFORMANCE STATE') AS view_server_performance_state,
           IS_SRVROLEMEMBER(N'sysadmin') AS is_sysadmin;
    REVERT;"

echo
echo "== A change without the password"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0, @publisher_login = N'm10_logreader';" 2>&1 | filter
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT publisher_login, DATALENGTH(publisher_password) AS password_bytes FROM dbo.MSlogreader_agents;"
t=$(since)
restart_job $logreader
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSlogreader_history WHERE time >= '$t' AND runstatus = 6" 1 90
history logreader "$t"
echo "-- the password given again"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @publisher_security_mode = 0,
         @publisher_login = N'm10_logreader', @publisher_password = N'LogReader-2026!m10';" 2>&1 | filter
restart_job $logreader
wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%' AND login_name = N'm10_logreader'" 1 60
agent_logins | grep LogReader

echo
echo "== A @job_login under Linux"
echo "-- a local account"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @job_login = N'rpllab2\m10_agent', @job_password = N'Agent-2026!m10';" 2>&1 | filter || true
echo "-- the account of the SQL Server Agent service"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_changelogreader_agent @job_login = N'NT AUTHORITY\NETWORK SERVICE', @job_password = N'Agent-2026!m10';" 2>&1 | filter
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT js.step_id, p.name AS proxy FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
    LEFT JOIN msdb.dbo.sysproxies p ON p.proxy_id = js.proxy_id WHERE j.name = N'$logreader' AND js.step_id = 2;"
t=$(sql rpllab2 -h -1 -Q "SET NOCOUNT ON; SELECT MAX(instance_id) FROM msdb.dbo.sysjobhistory;" | tr -d '[:space:]')
restart_job $logreader
wait_for rpllab2 "SELECT IIF(COUNT(*) > 0, 1, 0) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
                  WHERE j.name = N'$logreader' AND h.instance_id > $t AND h.step_id = 2 AND h.message LIKE N'%proxy%'" 1 60
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.step_id, h.run_status, LEFT(h.message, 200) AS message FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
    WHERE j.name = N'$logreader' AND h.instance_id > $t AND h.step_id = 2 AND h.message LIKE N'%proxy%' ORDER BY h.instance_id;"
echo "-- undone: no procedure of replication removes the proxy; the job step does"
stop_job $logreader
sql rpllab2 -Q "SET NOCOUNT ON;
    DECLARE @p sysname = (SELECT p.name FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id
                          JOIN msdb.dbo.sysproxies p ON p.proxy_id = js.proxy_id WHERE j.name = N'$logreader' AND js.step_id = 2);
    DECLARE @c sysname = (SELECT c.name FROM msdb.dbo.sysproxies p JOIN sys.credentials c ON c.credential_id = p.credential_id WHERE p.name = @p);
    EXEC msdb.dbo.sp_update_jobstep @job_name = N'$logreader', @step_id = 2, @proxy_name = N'';
    EXEC msdb.dbo.sp_delete_proxy @proxy_name = @p;
    DECLARE @q nvarchar(400) = N'DROP CREDENTIAL ' + QUOTENAME(@c);
    EXEC (@q);
    SELECT COUNT(*) AS proxies_left FROM msdb.dbo.sysproxies WHERE name LIKE N'%$logreader%';"
start_job $logreader
wait_for rpllab1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%' AND login_name = N'm10_logreader'" 1 60
agent_logins
