#!/usr/bin/env bash
# Module 5, clip 5.1. The reporting server subscribes by itself: a pull subscription of
# PachaReporting on rpllab3 to pubCatalog, whose Distribution Agent runs on the subscriber.
# First where the push agent of PachaCatalog runs (on the distributor). Then a pull
# subscription to a publication that does not allow pull: registered at the subscriber, refused
# at the publisher (Msg 20012), and the registration it leaves, removed. Then the pull
# subscription to pubCatalog with the defaults of sp_addpullsubscription_agent: under Linux the
# agent cannot connect to the distributor with Windows authentication (Agent message code
# 20084); the subscription is given the SQL Server login of the lab, and the snapshot arrives.
# Last, where the two agents are, and a tracer token that reaches both subscribers.
# Needs 00-setup.sh first.
# Usage: ./demos/module_05/01-pull.sh     (with Podman: ENGINE=podman ./demos/module_05/01-pull.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
filter() {  # sqlcmd output without the DBCC line and the warning on the database master key (module 10)
    grep -v "^DBCC\|^WARNING" || true
}
jobs() {  # the replication jobs of an instance and their schedule
    sql $1 -Q "SET NOCOUNT ON;
        SELECT N'$1' AS instance, j.name AS job, c.name AS category, s.freq_type
        FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
        LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
        LEFT JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
        WHERE c.name IN (N'REPL-LogReader', N'REPL-Snapshot', N'REPL-Distribution') ORDER BY c.name, j.name;"
}
pull_registrations() {  # what the subscription database knows of its pull subscriptions
    sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
        IF OBJECT_ID(N'dbo.MSreplication_subscriptions') IS NULL SELECT N'no MSreplication_subscriptions table' AS registrations;
        ELSE SELECT publisher, publisher_db, publication, subscription_type FROM dbo.MSreplication_subscriptions;"
}

echo "== rpllab2: the agents of a push subscription run on the distributor"
jobs rpllab2

echo
echo "== rpllab1: a publication that keeps the default of @allow_pull"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpublication @publication = N'm05_pubNoPull', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @independent_agent = N'true';
    EXEC sys.sp_addarticle @publication = N'm05_pubNoPull', @article = N'Category', @source_owner = N'Course', @source_object = N'Category';
    SELECT name, allow_push, allow_pull FROM dbo.syspublications ORDER BY name;" 2>&1 | filter
echo "-- rpllab3: the pull subscription, registered at the subscriber"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'm05_pubNoPull', @subscription_type = N'pull';" 2>&1 | filter
echo "-- rpllab1: the same subscription at the publisher"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_addsubscription @publication = N'm05_pubNoPull', @subscriber = N'rpllab3',
     @destination_db = N'PachaReporting', @subscription_type = N'pull', @sync_type = N'automatic', @article = N'all';" 2>&1 \
     | filter || true
echo "-- rpllab3: the registration is still there"
pull_registrations
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_droppullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining', @publication = N'm05_pubNoPull';"
echo "-- rpllab3: after sp_droppullsubscription"
pull_registrations
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON; EXEC sys.sp_droppublication @publication = N'm05_pubNoPull';"

echo
echo "== The pull subscription to pubCatalog, publisher first (the order of Learn)"
echo "-- rpllab1"
sql rpllab1 -d PachadataTraining -Q "SET NOCOUNT ON;
    EXEC sys.sp_addsubscription @publication = N'pubCatalog', @subscriber = N'rpllab3',
         @destination_db = N'PachaReporting', @subscription_type = N'pull', @sync_type = N'automatic', @article = N'all';" 2>&1 | filter
echo "-- rpllab3: the subscription and its agent, with the default connection to the distributor"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_addpullsubscription @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @subscription_type = N'pull';
    EXEC sys.sp_addpullsubscription_agent @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @distributor = N'rpllab2', @frequency_type = 64;" 2>&1 | filter
echo "-- rpllab1: a snapshot for the new subscription"
sql rpllab1 -d PachadataTraining -Q "EXEC sys.sp_startpublication_snapshot @publication = N'pubCatalog';"
job="(SELECT j.job_id FROM msdb.dbo.sysjobs j WHERE j.name LIKE N'%-PachaReporting-%')"
wait_for rpllab3 "SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.sysjobhistory WHERE job_id = $job AND message LIKE N'%Agent message code%'), 1, 0)" 1 120
echo "-- rpllab3: the output of the agent, in the history of its job"
sql rpllab3 -Q "SET NOCOUNT ON;
    SELECT TOP (1) h.message INTO #m FROM msdb.dbo.sysjobhistory h
    WHERE h.job_id = $job AND h.message LIKE N'%Agent message code%' ORDER BY h.instance_id DESC;
    SELECT LTRIM(REPLACE(value, CHAR(13), N'')) AS agent_output FROM #m CROSS APPLY STRING_SPLIT(message, CHAR(10))
    WHERE value LIKE N'%Security%' OR value LIKE N'%Connecting%' OR value LIKE N'%message code%';"
echo "-- rpllab3: the connection of the agent to the distributor"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    SELECT publication, distributor, distributor_security_mode, distributor_login FROM dbo.MSsubscription_properties;"

echo
echo "== rpllab3: the agent gets the SQL Server login of the lab"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    EXEC sys.sp_change_subscription_properties @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @property = N'distributor_login', @value = N'sa';
    EXEC sys.sp_change_subscription_properties @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @property = N'distributor_password', @value = N'Repl-2026!lab';
    EXEC sys.sp_change_subscription_properties @publisher = N'rpllab1', @publisher_db = N'PachadataTraining',
         @publication = N'pubCatalog', @property = N'distributor_security_mode', @value = N'0';
    SELECT publication, distributor, distributor_security_mode, distributor_login,
           IIF(distributor_password IS NULL, N'none', N'stored') AS distributor_password
    FROM dbo.MSsubscription_properties;" 2>&1 | filter
want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Course.Session" | tr -d '[:space:]')
# The job retries every minute: the next attempt reads the new connection.
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM PachaReporting.sys.partitions WHERE object_id = OBJECT_ID(N'PachaReporting.Course.Session') AND index_id < 2), -1)" "$want" 150
echo "-- rpllab2: the history of the pull agent, written in distribution"
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT h.runstatus, CONVERT(char(23), h.time, 121) AS time, LEFT(h.comments, 150) AS comments
    FROM dbo.MSdistribution_history h JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE a.subscriber_db = N'PachaReporting' AND h.comments NOT LIKE N'Bulk cop%' AND h.comments NOT LIKE N'Applied script%'
    ORDER BY h.timestamp;"
echo "-- rpllab3: the rows"
sql rpllab3 -d PachaReporting -Q "SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM Course.Category) AS Category, (SELECT COUNT(*) FROM Course.Course) AS Course,
           (SELECT COUNT(*) FROM Course.Session) AS Session;"

echo
echo "== Where the agents are"
jobs rpllab2
jobs rpllab3
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT a.subscriber_db, a.subscription_type, IIF(a.subscription_type = 0, N'push', N'pull') AS type, a.name AS agent
    FROM dbo.MSdistribution_agents a WHERE a.publication = N'pubCatalog' ORDER BY a.id;"

echo
echo "== rpllab1: one tracer token, two subscribers"
id=$(sql rpllab1 -d PachadataTraining -h -1 -Q "SET NOCOUNT ON; DECLARE @id int;
    EXEC sys.sp_posttracertoken @publication = N'pubCatalog', @tracer_token_id = @id OUTPUT; SELECT @id;" | tr -d '[:space:]')
wait_for rpllab2 "SELECT COUNT(*) FROM distribution.dbo.MStracer_history WHERE parent_tracer_id = $id AND subscriber_commit IS NOT NULL" 2 120
sql rpllab2 -d distribution -Q "SET NOCOUNT ON;
    SELECT a.subscriber_db, IIF(a.subscription_type = 0, N'push', N'pull') AS type,
           DATEDIFF(second, t.publisher_commit, t.distributor_commit) AS distributor_latency_s,
           DATEDIFF(second, t.distributor_commit, h.subscriber_commit) AS subscriber_latency_s
    FROM dbo.MStracer_tokens t JOIN dbo.MStracer_history h ON h.parent_tracer_id = t.tracer_id
    JOIN dbo.MSdistribution_agents a ON a.id = h.agent_id
    WHERE t.tracer_id = $id ORDER BY a.id;"
