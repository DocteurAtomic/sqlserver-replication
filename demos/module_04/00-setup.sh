#!/usr/bin/env bash
# Module 4, setup. The module starts from the distributor of module 2. 99-cleanup.sh first removes
# whatever a previous module or run left, and gives the catalog back as it was. Then:
# setup/repl-distributor.sh builds the distributor on rpllab2 with rpllab1 as its publisher; on
# rpllab1, the database of the module, m04_Journal, keeps the prices of Course.Session
# (dbo.SessionBefore, read by 99-cleanup.sh to undo the demos) and a small table, dbo.Note,
# that clip 4.2 publishes to read what the Log Reader Agent reads; on rpllab3, the database of
# the registration site, PachaCatalog, is created empty.
# Usage: ./demos/module_04/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_04/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_04/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE m04_Journal;"
sql rpllab1 -d m04_Journal -Q "SET NOCOUNT ON;
    SELECT SessionId, Price INTO dbo.SessionBefore FROM PachadataTraining.Course.Session;
    CREATE TABLE dbo.Note (NoteId int IDENTITY CONSTRAINT pk_Note PRIMARY KEY, Body nvarchar(200) NOT NULL);
    SELECT COUNT(*) AS sessions_saved, MAX(SessionId) AS last_session FROM dbo.SessionBefore;"
sql rpllab3 -Q "SET NOCOUNT ON;
    CREATE DATABASE PachaCatalog;
    SELECT name, recovery_model_desc FROM sys.databases WHERE name = N'PachaCatalog';"
