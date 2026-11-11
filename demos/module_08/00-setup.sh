#!/usr/bin/env bash
# Module 8, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog, pushed to PachaCatalog on rpllab3. On rpllab1, the database of the
# module, m08_Journal (full recovery, a full backup taken so that the log is kept until a log
# backup), keeps the prices of Course.Session (dbo.SessionBefore, read by 99-cleanup.sh to undo
# the demos) and a table, dbo.Event, published by m08_pubJournal (its own Log Reader Agent) to
# m08_Journal on rpllab3: clip 8.1 stops that Log Reader Agent, and clip 8.4 lets that
# subscription expire, without touching the log of PachadataTraining.
# Usage: ./demos/module_08/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_08/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_08/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE m08_Journal; ALTER DATABASE m08_Journal SET RECOVERY FULL;"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON;
    SELECT SessionId, Price INTO dbo.SessionBefore FROM PachadataTraining.Course.Session;
    CREATE TABLE dbo.Event (EventId int IDENTITY CONSTRAINT pk_Event PRIMARY KEY,
                            CreatedAt datetime2(0) NOT NULL CONSTRAINT df_Event_CreatedAt DEFAULT SYSDATETIME(),
                            Body char(200) NOT NULL);
    BACKUP DATABASE m08_Journal TO DISK = N'/var/opt/mssql/data/m08_Journal.bak' WITH INIT, FORMAT;" > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m08_Journal;"
sql rpllab1 -d m08_Journal -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm08_Journal', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addpublication @publication = N'm08_pubJournal', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'false';
    EXEC sys.sp_addpublication_snapshot @publication = N'm08_pubJournal', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm08_pubJournal', @article = N'Event', @source_owner = N'dbo', @source_object = N'Event';
    EXEC sys.sp_addsubscription @publication = N'm08_pubJournal', @subscriber = N'rpllab3',
         @destination_db = N'm08_Journal', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm08_pubJournal', @subscriber = N'rpllab3',
         @subscriber_db = N'm08_Journal', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
    EXEC sys.sp_startpublication_snapshot @publication = N'm08_pubJournal';" > /dev/null
wait_for rpllab3 "SELECT IIF(OBJECT_ID(N'm08_Journal.dbo.Event') IS NULL, 0, 1)" 1 180
echo "m08_pubJournal delivered: dbo.Event of m08_Journal on rpllab3"
