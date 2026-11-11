#!/usr/bin/env bash
# Module 10, clip 10.2. The publication access list and the snapshot folder. The PAL of
# pubCatalog read on the publisher (sp_help_publication_access, the role MSReplPAL_<dbid>_<pubid>)
# and its copy on the distributor (MSpublication_access); distributor_admin, which is not in
# it and owns the agent jobs. Then a pull subscription, m10_Reporting on rpllab3, whose
# Distribution Agent connects to the distributor with a SQL Server login, m10_pull: refused
# while the login is not in the PAL (Agent message code 14080), what sp_grant_publication_access
# asks for (the login and a user in the publication database), the snapshot delivered once the
# login is in the PAL, refused again after sp_revoke_publication_access. Last, the snapshot
# folder: the files of the snapshot read in clear on the shared volume, and the Snapshot Agent
# refused when its folder is read-only. 03-secrets.sh uses m10_pull and m10_Reporting.
# Needs 00-setup.sh and 01-accounts.sh first.
# Usage: ./demos/module_10/02-pal.sh     (with Podman: ENGINE=podman ./demos/module_10/02-pal.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
. demos/module_10/lib.sh
pull_job() {  # the job of the pull Distribution Agent, on rpllab3
    sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'%-m10[_]Reporting-%';" | tr -d '[:space:]'
}
pull_message() {  # the last agent message code in the history of the pull job, written after a history id
    sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT TOP (1) h.message INTO #m FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
        WHERE j.name = N'$1' AND h.instance_id > $2 AND h.message LIKE N'%Agent message code%' ORDER BY h.instance_id DESC;
        SELECT LTRIM(REPLACE(value, CHAR(13), N'')) FROM #m CROSS APPLY STRING_SPLIT(message, CHAR(10))
        WHERE value LIKE N'%Connecting%' OR value LIKE N'%message code%';" | sed '/^$/d'
}
last_history() { sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(MAX(instance_id), 0) FROM msdb.dbo.sysjobhistory;" | tr -d '[:space:]'; }

echo "== rpllab1: the PAL of pubCatalog"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_help_publication_access @publication = N'pubCatalog';
    SELECT name AS role FROM sys.database_principals WHERE type = 'R' AND (name LIKE N'MSReplPAL%' OR name LIKE N'MStran_PAL%');"
echo "-- rpllab2: its copy on the distributor"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT p.publication, pa.login FROM dbo.MSpublication_access pa JOIN dbo.MSpublications p ON p.publication_id = pa.publication_id;"
echo "-- distributor_admin: a login of the distributor, used by the publisher's link"
sql rpllab1 -Q "SET NOCOUNT ON;
    SELECT s.name AS linked_server, l.remote_name FROM sys.servers s JOIN sys.linked_logins l ON l.server_id = s.server_id
    WHERE s.name = N'repl_distributor';
    SELECT COUNT(*) AS distributor_admin_logins_on_rpllab1 FROM sys.server_principals WHERE name = N'distributor_admin';"
sql rpllab2 -Q "SET NOCOUNT ON;
    SELECT name, IS_SRVROLEMEMBER(N'sysadmin', name) AS is_sysadmin FROM sys.server_principals WHERE name = N'distributor_admin';
    SELECT SUSER_SNAME(owner_sid) AS owner_of_agent_jobs, COUNT(*) AS jobs FROM msdb.dbo.sysjobs j
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id WHERE c.name LIKE N'REPL-%' GROUP BY SUSER_SNAME(owner_sid);"

echo
echo "== A pull subscription whose agent connects to the distributor as m10_pull"
sql rpllab2 -Q "SET NOCOUNT ON; CREATE LOGIN m10_pull WITH PASSWORD = N'Pull-2026!m10', CHECK_POLICY = OFF;"
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m10_Reporting;"
sql rpllab3 -d m10_Reporting -Q "SET NOCOUNT ON; EXEC (N'CREATE SCHEMA Course');"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3',
         @destination_db = N'm10_Reporting', @subscription_type = N'pull', @sync_type = N'automatic', @article = N'all';" 2>&1 | filter
h=$(last_history)
sql rpllab3 -d m10_Reporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @subscription_type = N'pull';
    EXEC sys.sp_addpullsubscription_agent @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @distributor = N'rpllab2', @distributor_security_mode = 0,
         @distributor_login = N'm10_pull', @distributor_password = N'Pull-2026!m10', @frequency_type = 64;" 2>&1 | filter
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';" | filter
job=$(pull_job)
wait_for rpllab3 "SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
                  WHERE j.name = N'$job' AND h.instance_id > $h AND h.message LIKE N'%Agent message code%'" 1 120
echo "-- rpllab3: the pull agent, m10_pull exists on the distributor only"
pull_message "$job" "$h"
echo "-- rpllab1: m10_pull into the PAL"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_grant_publication_access @publication = N'pubCatalog', @login = N'm10_pull';" 2>&1 | filter || true
sql rpllab1 -Q "SET NOCOUNT ON; CREATE LOGIN m10_pull WITH PASSWORD = N'Pull-2026!m10', CHECK_POLICY = OFF;"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_grant_publication_access @publication = N'pubCatalog', @login = N'm10_pull';" 2>&1 | filter || true
echo "-- rpllab1: m10_pull is not in the PAL yet"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; CREATE USER m10_pull FOR LOGIN m10_pull;
    EXECUTE AS LOGIN = N'm10_pull'; EXEC sys.sp_helppublication @publication = N'pubCatalog'; REVERT;" 2>&1 | grep -v "^pubid\|^-----" | filter
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_grant_publication_access @publication = N'pubCatalog', @login = N'm10_pull';
    EXEC sys.sp_help_publication_access @publication = N'pubCatalog';
    SELECT m.name AS member_of_MSReplPAL FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id WHERE r.name LIKE N'MSReplPAL%';" 2>&1 | filter
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT pa.login AS PAL_on_rpllab2 FROM dbo.MSpublication_access pa ORDER BY pa.login;
    EXECUTE AS LOGIN = N'm10_pull'; SELECT USER_NAME() AS user_in_distribution, IS_MEMBER(N'db_owner') AS is_db_owner; REVERT;"
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
# The job retries every minute: the next attempt reads the PAL.
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM m10_Reporting.sys.partitions WHERE object_id = OBJECT_ID(N'm10_Reporting.Course.Session') AND index_id < 2), -1)" "$want" 150
echo "-- rpllab3: delivered"
sql rpllab3 -d m10_Reporting -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM Course.Category) AS Category, (SELECT COUNT(*) FROM Course.Course) AS Course,
           (SELECT COUNT(*) FROM Course.Session) AS Session;"
sql rpllab2 -Q "SET NOCOUNT ON; SELECT DISTINCT login_name, program_name FROM sys.dm_exec_sessions WHERE login_name = N'm10_pull';"
echo "-- rpllab1: m10_pull out of the PAL, the agent restarted"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_revoke_publication_access @publication = N'pubCatalog', @login = N'm10_pull';" 2>&1 | filter
h=$(last_history)
sql rpllab3 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
wait_for rpllab3 "SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id WHERE j.name = N'$job'
                  AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" 0 60
sql rpllab3 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
wait_for rpllab3 "SELECT COUNT(*) FROM msdb.dbo.sysjobhistory h JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
                  WHERE j.name = N'$job' AND h.instance_id > $h AND h.message LIKE N'%Agent message code%'" 1 120
pull_message "$job" "$h"
echo "-- rpllab1: back into the PAL (03-secrets.sh uses this subscription)"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_grant_publication_access @publication = N'pubCatalog', @login = N'm10_pull';" 2>&1 | filter

echo
echo "== The snapshot folder"
dir=$($engine exec rpllab3 sh -c 'ls -d /var/opt/mssql/share/repldata/unc/*/* | tail -1')
echo "-- rpllab3: the last snapshot of pubCatalog, on the volume shared by the three containers"
$engine exec rpllab3 ls -l "$dir" | grep -v "Session_4#" | sed 's/^\([-drwx.]*\) *[0-9]* /\1 /'
$engine exec rpllab3 sh -c "ls '$dir' | grep -c '^Session_4#'" | sed 's/^/Session_4#*.bcp files: /'
echo "-- rpllab3: Category_2.bcp, printable characters only"
$engine exec rpllab3 sh -c "tr -c '[:print:]' '.' < '$dir/Category_2.bcp'"; echo
echo "-- rpllab3: the start of Course_3.sch"
$engine exec rpllab3 sh -c "iconv -f UTF-16LE -t UTF-8 '$dir/Course_3.sch' 2>/dev/null || cat '$dir/Course_3.sch'" | tr -d '\r' | grep -m 6 -i "create table\|^\s*\[" || true
echo "-- rpllab2: the folder of the publication made read-only, a subscription to initialize"
pubdir=$(dirname "$dir")
$engine exec -u 0 rpllab2 chmod 0555 "$pubdir"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_reinitsubscription @publication = N'pubCatalog', @article = N'all', @subscriber = N'rpllab3', @destination_db = N'PachaCatalog';" 2>&1 | filter
t=$(since)
start_job $snapshot
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history WHERE time >= '$t' AND runstatus IN (2, 6)" 1 90
history snapshot "$t" | grep -v "Azure Storage"
echo "-- rpllab2: the folder writable again"
$engine exec -u 0 rpllab2 chmod 0755 "$pubdir"
wait_for rpllab2 "$(running $snapshot)" 0 60
t=$(since)
start_job $snapshot
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSsnapshot_history WHERE time >= '$t' AND runstatus IN (2, 6)" 1 120
history snapshot "$t" | tail -1
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history h JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                  WHERE a.name = N'$distrib' AND h.time >= '$t' AND h.comments LIKE N'Delivered snapshot%'" 1 180
history $distrib "$t" | grep "Delivered snapshot"
