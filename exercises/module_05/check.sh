#!/usr/bin/env bash
# Exercise of module 5: checks the pull subscription asked for. It reads the state of the three
# instances, never a script. On rpllab1: the category PL in Course.Category. On rpllab2: a pull
# subscription of ex_pull to ex_pubCatalog in the distribution database, no Distribution Agent
# job for it on the distributor, its agent's last history line not an error, and a tracer token
# of ex_pubCatalog that this agent delivered. On rpllab3: the job of the agent, running, the
# category PL in ex_pull, and the three tables with the same rows as on rpllab1 (row count and
# CHECKSUM_AGG of BINARY_CHECKSUM, compared table by table).
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_05/check.sh     (with Podman: ENGINE=podman ./exercises/module_05/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tables="Category Course Session"
out1=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON;
    SELECT IIF(EXISTS (SELECT * FROM PachadataTraining.Course.Category WHERE CategoryCode = 'PL'),
               N'OK   the category PL in Course.Category on rpllab1 (the change asked for)',
               N'FAIL the category PL is not in Course.Category on rpllab1 (the change asked for)');" 2>&1 | sed '/^$/d')
out2=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF DB_ID(N'distribution') IS NULL
    INSERT @r VALUES (0, N'a pull subscription of ex_pull to ex_pubCatalog: no distribution database'),
                     (0, N'no Distribution Agent job of ex_pull on the distributor: no distribution database'),
                     (0, N'the Distribution Agent of ex_pull has delivered the snapshot, without error: no distribution database'),
                     (0, N'a tracer token of ex_pubCatalog delivered to ex_pull: no distribution database');
ELSE
BEGIN
    DECLARE @agent int = (SELECT TOP (1) a.id FROM distribution.dbo.MSdistribution_agents a
                          WHERE a.subscriber_db = N'ex_pull' AND a.publication = N'ex_pubCatalog' ORDER BY a.id DESC);
    -- MSsubscriptions.subscription_type: 0 push, 1 pull.
    DECLARE @type int = (SELECT MAX(s.subscription_type) FROM distribution.dbo.MSsubscriptions s
                         JOIN distribution.dbo.MSpublications p ON p.publication_id = s.publication_id
                         WHERE s.subscriber_db = N'ex_pull' AND p.publication = N'ex_pubCatalog');
    INSERT @r SELECT IIF(@type = 1, 1, 0),
        CONCAT(N'a pull subscription of ex_pull to ex_pubCatalog (subscription_type ',
               ISNULL(CAST(@type AS nvarchar(5)), N'none'), N'; 1 is pull, 0 push)');
    DECLARE @jobs int = (SELECT COUNT(*) FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
                         WHERE c.name = N'REPL-Distribution' AND j.name LIKE N'%ex[_]pubCatalog%' AND j.name LIKE N'%ex[_]pull%');
    INSERT @r SELECT IIF(@jobs = 0, 1, 0),
        CONCAT(N'no Distribution Agent job of ex_pull on the distributor (found: ', @jobs, N')');
    DECLARE @delivered int = (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history
                              WHERE agent_id = @agent AND comments LIKE N'Delivered snapshot%');
    DECLARE @last int = (SELECT TOP (1) runstatus FROM distribution.dbo.MSdistribution_history
                         WHERE agent_id = @agent ORDER BY timestamp DESC);
    -- runstatus 6 is a failure; 1 start, 2 succeed, 3 in progress, 4 idle, 5 retry.
    INSERT @r SELECT IIF(@delivered > 0 AND @last IN (1, 2, 3, 4), 1, 0),
        CONCAT(N'the Distribution Agent of ex_pull has delivered the snapshot, without error (snapshot delivered: ',
               IIF(@delivered > 0, N'yes', N'no'), N', last runstatus: ', ISNULL(CAST(@last AS nvarchar(5)), N'none'),
               N'; 5 retry, 6 failure)');
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MStracer_history h
                                 JOIN distribution.dbo.MStracer_tokens t ON t.tracer_id = h.parent_tracer_id
                                 JOIN distribution.dbo.MSpublications p ON p.publication_id = t.publication_id
                                 WHERE p.publication = N'ex_pubCatalog' AND h.agent_id = @agent
                                   AND h.subscriber_commit IS NOT NULL), 1, 0),
        N'a tracer token of ex_pubCatalog delivered to ex_pull (MStracer_history.subscriber_commit)';
END;
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
# rpllab3: the job of the pull agent, then the category PL, then each table compared with
# rpllab1. The table is looked for first: a query that names a table that does not exist fails
# to compile, whatever its CASE says.
out3=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
    DECLARE @n int = (SELECT COUNT(*) FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id
                      JOIN msdb.dbo.sysjobactivity a ON a.job_id = j.job_id
                      WHERE c.name = N'REPL-Distribution' AND j.name LIKE N'%-ex[_]pubCatalog-%' AND j.name LIKE N'%-ex[_]pull-%'
                        AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL
                        AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions));
    SELECT IIF(@n = 1, N'OK   the Distribution Agent of ex_pull runs on rpllab3',
               CONCAT(N'FAIL the Distribution Agent of ex_pull runs on rpllab3 (running jobs found: ', @n, N')'));" 2>&1 | sed '/^$/d')
line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
    SELECT CASE WHEN DB_ID(N'ex_pull') IS NULL THEN N'FAIL the category PL in ex_pull: no database ex_pull on rpllab3'
                WHEN OBJECT_ID(N'ex_pull.Course.Category') IS NULL THEN N'FAIL the category PL in ex_pull: no table Course.Category'
                ELSE N'' END;" 2>&1 | sed '/^$/d')
if [ -z "$line" ]; then
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT IIF(EXISTS (SELECT * FROM ex_pull.Course.Category WHERE CategoryCode = 'PL'),
                   N'OK   the category PL arrived in ex_pull', N'FAIL the category PL has not arrived in ex_pull');" 2>&1 | sed '/^$/d')
fi
out3="$out3"$'\n'"$line"
for t in $tables; do
    q="SET NOCOUNT ON; SELECT CONCAT(COUNT(*), ' rows, checksum ', CHECKSUM_AGG(BINARY_CHECKSUM(*))) FROM"
    want=$(sql rpllab1 -h -1 -Q "$q PachadataTraining.Course.$t;" 2>&1 | sed '/^$/d')
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT CASE WHEN DB_ID(N'ex_pull') IS NULL THEN N'FAIL ex_pull.Course.$t: no database ex_pull on rpllab3'
                    WHEN OBJECT_ID(N'ex_pull.Course.$t') IS NULL THEN N'FAIL ex_pull.Course.$t: no such table on rpllab3'
                    ELSE N'' END;" 2>&1 | sed '/^$/d')
    if [ -z "$line" ]; then
        got=$(sql rpllab3 -h -1 -Q "$q ex_pull.Course.$t;" 2>&1 | sed '/^$/d')
        if [ "$got" = "$want" ]; then line="OK   ex_pull.Course.$t has the rows of the publisher ($got)"
        else line="FAIL ex_pull.Course.$t: $got on rpllab3, $want on rpllab1"; fi
    fi
    out3="$out3"$'\n'"$line"
done
# One check on rpllab1, four on rpllab2, five on rpllab3: a missing line or an error message is
# a failure, so that a check that did not run is never taken for one that passed.
fail=0
for pair in "1:$out1" "4:$out2" "5:$out3"; do
    want=${pair%%:*}; o=${pair#*:}
    echo "$o"
    got=$(echo "$o" | grep -cE '^(OK|FAIL) ')
    if [ "$got" -ne "$want" ] || echo "$o" | grep -q '^Msg '; then
        echo "FAIL $got checks out of $want ran"; fail=1
    fi
    echo "$o" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The pull subscription of the exercise is not complete."; exit 1; fi
echo "ex_pull receives ex_pubCatalog from its own Distribution Agent, change and tracer token included."
