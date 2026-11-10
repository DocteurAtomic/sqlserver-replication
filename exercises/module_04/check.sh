#!/usr/bin/env bash
# Exercise of module 4: checks the transactional publication asked for. It reads the state of the
# three instances, never a script. On rpllab1: a transactional publication ex_pubCatalog,
# active, with concurrent snapshot processing, whose articles are exactly Course.Category,
# Course.Course and Course.Session, and the category EX in Course.Category. On rpllab2: the
# Distribution Agent of ex_catalog scheduled to run continuously, running, its last history line
# not an error, and a tracer token of ex_pubCatalog that reached the subscriber. On rpllab3: the
# category EX in ex_catalog, and the three tables with the same rows as on rpllab1 (row count and
# CHECKSUM_AGG of BINARY_CHECKSUM, compared table by table).
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_04/check.sh     (with Podman: ENGINE=podman ./exercises/module_04/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tables="Category Course Session"
out1=$(sql rpllab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
USE PachadataTraining;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF OBJECT_ID(N'dbo.syspublications') IS NULL
    INSERT @r VALUES (0, N'a transactional publication ex_pubCatalog in PachadataTraining: the database publishes nothing'),
                     (0, N'ex_pubCatalog is active, with @sync_method = concurrent'),
                     (0, N'the articles of ex_pubCatalog are Course.Category, Course.Course, Course.Session');
ELSE
BEGIN
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM dbo.syspublications WHERE name = N'ex_pubCatalog' AND repl_freq = 0), 1, 0),
        N'a transactional publication ex_pubCatalog in PachadataTraining (@repl_freq = continuous)';
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM dbo.syspublications WHERE name = N'ex_pubCatalog' AND status = 1 AND sync_method = 3), 1, 0),
        CONCAT(N'ex_pubCatalog is active, with @sync_method = concurrent (found: status ',
               ISNULL((SELECT CAST(status AS nvarchar(5)) FROM dbo.syspublications WHERE name = N'ex_pubCatalog'), N'none'),
               N', sync_method ',
               ISNULL((SELECT CAST(sync_method AS nvarchar(5)) FROM dbo.syspublications WHERE name = N'ex_pubCatalog'), N'none'),
               N'; 1 and 3 expected)');
    DECLARE @arts nvarchar(400) = (SELECT STRING_AGG(OBJECT_SCHEMA_NAME(a.objid) + N'.' + OBJECT_NAME(a.objid), N', ')
                                          WITHIN GROUP (ORDER BY OBJECT_NAME(a.objid))
                                   FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                                   WHERE p.name = N'ex_pubCatalog');
    INSERT @r SELECT IIF(@arts = N'Course.Category, Course.Course, Course.Session', 1, 0),
        CONCAT(N'the articles of ex_pubCatalog are Course.Category, Course.Course, Course.Session (found: ',
               ISNULL(@arts, N'none'), N')');
END;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM Course.Category WHERE CategoryCode = 'EX'), 1, 0),
    N'the category EX in Course.Category on rpllab1 (the change asked for)';
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
out2=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF DB_ID(N'distribution') IS NULL
    INSERT @r VALUES (0, N'the Distribution Agent of ex_catalog runs continuously: no distribution database'),
                     (0, N'the Distribution Agent of ex_catalog is running without error: no distribution database'),
                     (0, N'a tracer token of ex_pubCatalog reached the subscriber: no distribution database');
ELSE
BEGIN
    -- freq_type 64: start when the Agent starts, and keep running (-Continuous).
    INSERT @r SELECT ISNULL(MAX(IIF(s.freq_type = 64, 1, 0)), 0),
        CONCAT(N'the Distribution Agent of ex_catalog runs continuously (freq_type ',
               ISNULL(CAST(MAX(s.freq_type) AS nvarchar(5)), N'none'), N'; 64 expected)')
    FROM distribution.dbo.MSdistribution_agents a
    JOIN msdb.dbo.sysjobschedules js ON js.job_id = CAST(a.job_id AS uniqueidentifier)
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE a.subscriber_db = N'ex_catalog';
    DECLARE @running int = (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_agents a
                            JOIN msdb.dbo.sysjobactivity ja ON ja.job_id = CAST(a.job_id AS uniqueidentifier)
                            WHERE a.subscriber_db = N'ex_catalog' AND ja.start_execution_date IS NOT NULL
                              AND ja.stop_execution_date IS NULL
                              AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions));
    DECLARE @last int = (SELECT TOP (1) h.runstatus FROM distribution.dbo.MSdistribution_history h
                         JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                         WHERE a.subscriber_db = N'ex_catalog' ORDER BY h.timestamp DESC);
    -- runstatus 6 is a failure; 1 start, 2 succeed, 3 in progress, 4 idle, 5 retry.
    INSERT @r SELECT IIF(@running = 1 AND @last IN (1, 3, 4), 1, 0),
        CONCAT(N'the Distribution Agent of ex_catalog is running without error (job running: ', @running,
               N', last runstatus: ', ISNULL(CAST(@last AS nvarchar(5)), N'none'), N'; 6 is a failure)');
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MStracer_tokens t
                                 JOIN distribution.dbo.MStracer_history h ON h.parent_tracer_id = t.tracer_id
                                 JOIN distribution.dbo.MSpublications p ON p.publication_id = t.publication_id
                                 WHERE p.publication = N'ex_pubCatalog' AND h.subscriber_commit IS NOT NULL), 1, 0),
        N'a tracer token of ex_pubCatalog reached the subscriber (MStracer_history.subscriber_commit)';
END;
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
# rpllab3: the category EX, then each table compared with rpllab1. The table is looked for first:
# a query that names a table that does not exist fails to compile, whatever its CASE says.
line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
    SELECT CASE WHEN DB_ID(N'ex_catalog') IS NULL THEN N'FAIL the category EX in ex_catalog: no database ex_catalog on rpllab3'
                WHEN OBJECT_ID(N'ex_catalog.Course.Category') IS NULL THEN N'FAIL the category EX in ex_catalog: no table Course.Category'
                ELSE N'' END;" 2>&1 | sed '/^$/d')
if [ -z "$line" ]; then
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT IIF(EXISTS (SELECT * FROM ex_catalog.Course.Category WHERE CategoryCode = 'EX'),
                   N'OK   the category EX arrived in ex_catalog', N'FAIL the category EX has not arrived in ex_catalog');" 2>&1 | sed '/^$/d')
fi
out3="$line"$'\n'
for t in $tables; do
    q="SET NOCOUNT ON; SELECT CONCAT(COUNT(*), ' rows, checksum ', CHECKSUM_AGG(BINARY_CHECKSUM(*))) FROM"
    want=$(sql rpllab1 -h -1 -Q "$q PachadataTraining.Course.$t;" 2>&1 | sed '/^$/d')
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT CASE WHEN DB_ID(N'ex_catalog') IS NULL THEN N'FAIL ex_catalog.Course.$t: no database ex_catalog on rpllab3'
                    WHEN OBJECT_ID(N'ex_catalog.Course.$t') IS NULL THEN N'FAIL ex_catalog.Course.$t: no such table on rpllab3'
                    ELSE N'' END;" 2>&1 | sed '/^$/d')
    if [ -z "$line" ]; then
        got=$(sql rpllab3 -h -1 -Q "$q ex_catalog.Course.$t;" 2>&1 | sed '/^$/d')
        if [ "$got" = "$want" ]; then line="OK   ex_catalog.Course.$t has the rows of the publisher ($got)"
        else line="FAIL ex_catalog.Course.$t: $got on rpllab3, $want on rpllab1"; fi
    fi
    out3="$out3$line"$'\n'
done
out3=${out3%$'\n'}
# Four checks on rpllab1, three on rpllab2, four on rpllab3: a missing line or an error message
# is a failure, so that a check that did not run is never taken for one that passed.
fail=0
for pair in "4:$out1" "3:$out2" "4:$out3"; do
    want=${pair%%:*}; o=${pair#*:}
    echo "$o"
    got=$(echo "$o" | grep -cE '^(OK|FAIL) ')
    if [ "$got" -ne "$want" ] || echo "$o" | grep -q '^Msg '; then
        echo "FAIL $got checks out of $want ran"; fail=1
    fi
    echo "$o" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The transactional publication of the exercise is not complete."; exit 1; fi
echo "ex_pubCatalog delivers the catalog to ex_catalog, change and tracer token included."
