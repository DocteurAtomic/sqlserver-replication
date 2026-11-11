#!/usr/bin/env bash
# Module 9, setup. The module starts from the end of module 4: 99-cleanup.sh first removes
# whatever a previous module or run left, then setup/repl-catalog.sh builds the distributor and
# publication pubCatalog, pushed to PachaCatalog on rpllab3 (clip 9.1 sets the profile of its
# Distribution Agent). The database of the module, m09_Billing on rpllab1, holds a copy of
# 200,000 invoice lines of PachadataTraining (Enrollment.InvoiceLine), numbered by LineId, with a
# Status column, the
# month-end closing of clips 9.2 and 9.3; m09_pubBilling (its own Log Reader Agent) pushes it to
# m09_Billing on rpllab3. PachadataTraining is only read.
# Usage: ./demos/module_09/00-setup.sh     (with Podman: ENGINE=podman ./demos/module_09/00-setup.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_09/99-cleanup.sh > /dev/null
./setup/repl-catalog.sh
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE m09_Billing; ALTER DATABASE m09_Billing SET RECOVERY SIMPLE;"
sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
    SELECT TOP (200000) CAST(ROW_NUMBER() OVER (ORDER BY InvoiceCode, LineNumber) AS int) AS LineId,
           InvoiceCode, LineNumber, LineTypeCode, EnrollmentId, Label, Quantity, UnitPrice, NetAmount,
           CAST('OPEN' AS char(6)) AS Status
    INTO dbo.InvoiceLine FROM PachadataTraining.Enrollment.InvoiceLine ORDER BY InvoiceCode, LineNumber;
    ALTER TABLE dbo.InvoiceLine ALTER COLUMN LineId int NOT NULL;
    ALTER TABLE dbo.InvoiceLine ALTER COLUMN Status char(6) NOT NULL;
    ALTER TABLE dbo.InvoiceLine ADD CONSTRAINT pk_InvoiceLine PRIMARY KEY (LineId);" > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE m09_Billing; ALTER DATABASE m09_Billing SET RECOVERY SIMPLE;"
sql rpllab1 -d m09_Billing -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'm09_Billing', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addpublication @publication = N'm09_pubBilling', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'false';
    EXEC sys.sp_addpublication_snapshot @publication = N'm09_pubBilling', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'm09_pubBilling', @article = N'InvoiceLine', @source_owner = N'dbo', @source_object = N'InvoiceLine';
    EXEC sys.sp_addsubscription @publication = N'm09_pubBilling', @subscriber = N'rpllab3',
         @destination_db = N'm09_Billing', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'm09_pubBilling', @subscriber = N'rpllab3',
         @subscriber_db = N'm09_Billing', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
    EXEC sys.sp_startpublication_snapshot @publication = N'm09_pubBilling';" > /dev/null
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM m09_Billing.sys.partitions WHERE object_id = OBJECT_ID(N'm09_Billing.dbo.InvoiceLine') AND index_id < 2), -1)" 200000 240
echo "m09_pubBilling delivered: 200000 invoice lines of m09_Billing on rpllab3"
