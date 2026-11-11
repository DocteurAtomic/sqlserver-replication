#!/usr/bin/env bash
# Exercise of module 9, starting state. demos/module_09/99-cleanup.sh removes what the demos (or
# anything else) left, setup/repl-distributor.sh builds the distributor. On rpllab1, the
# database ex_billing holds 200,000 invoice lines copied from PachadataTraining
# (Enrollment.InvoiceLine), numbered by LineId, with a Status column; publication ex_pubBilling
# pushes them to ex_billing on rpllab3, and the script waits until the snapshot is delivered.
# The Distribution Agent of ex_billing runs with the default profile. About a minute and a half.
# demos/module_09/99-cleanup.sh removes everything at the end, the profiles of the exercise
# included (they go with the distributor).
# Usage: ./exercises/module_09/1-start.sh     (with Podman: ENGINE=podman ./exercises/module_09/1-start.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
./demos/module_09/99-cleanup.sh > /dev/null
./setup/repl-distributor.sh > /dev/null
sql rpllab1 -Q "SET NOCOUNT ON; CREATE DATABASE ex_billing; ALTER DATABASE ex_billing SET RECOVERY SIMPLE;"
sql rpllab1 -d ex_billing -Q "SET NOCOUNT ON;
    SELECT TOP (200000) CAST(ROW_NUMBER() OVER (ORDER BY InvoiceCode, LineNumber) AS int) AS LineId,
           InvoiceCode, LineNumber, LineTypeCode, EnrollmentId, Label, Quantity, UnitPrice, NetAmount,
           CAST('OPEN' AS char(6)) AS Status
    INTO dbo.InvoiceLine FROM PachadataTraining.Enrollment.InvoiceLine ORDER BY InvoiceCode, LineNumber;
    ALTER TABLE dbo.InvoiceLine ALTER COLUMN LineId int NOT NULL;
    ALTER TABLE dbo.InvoiceLine ALTER COLUMN Status char(6) NOT NULL;
    ALTER TABLE dbo.InvoiceLine ADD CONSTRAINT pk_InvoiceLine PRIMARY KEY (LineId);" > /dev/null
sql rpllab3 -Q "SET NOCOUNT ON; CREATE DATABASE ex_billing; ALTER DATABASE ex_billing SET RECOVERY SIMPLE;"
sql rpllab1 -d ex_billing -Q "SET NOCOUNT ON;
    EXEC sys.sp_replicationdboption @dbname = N'ex_billing', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addpublication @publication = N'ex_pubBilling', @repl_freq = N'continuous',
         @status = N'active', @sync_method = N'concurrent', @allow_push = N'true', @allow_pull = N'true',
         @independent_agent = N'true', @immediate_sync = N'false';
    EXEC sys.sp_addpublication_snapshot @publication = N'ex_pubBilling', @frequency_type = 1,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addarticle @publication = N'ex_pubBilling', @article = N'InvoiceLine', @source_owner = N'dbo', @source_object = N'InvoiceLine';
    EXEC sys.sp_addsubscription @publication = N'ex_pubBilling', @subscriber = N'rpllab3',
         @destination_db = N'ex_billing', @subscription_type = N'push', @sync_type = N'automatic', @article = N'all';
    EXEC sys.sp_addpushsubscription_agent @publication = N'ex_pubBilling', @subscriber = N'rpllab3',
         @subscriber_db = N'ex_billing', @subscriber_security_mode = 0,
         @subscriber_login = N'sa', @subscriber_password = N'Repl-2026!lab', @frequency_type = 64;
    EXEC sys.sp_startpublication_snapshot @publication = N'ex_pubBilling';" > /dev/null
wait_for rpllab3 "SELECT ISNULL((SELECT SUM(rows) FROM ex_billing.sys.partitions WHERE object_id = OBJECT_ID(N'ex_billing.dbo.InvoiceLine') AND index_id < 2), -1)" 200000 240
echo "ex_pubBilling delivered: 200000 invoice lines of ex_billing on rpllab3, Distribution Agent on the default profile."
echo "Play the month-end closing: ./exercises/module_09/tools/month-end.sh"
