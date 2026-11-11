#!/usr/bin/env bash
# Exercise of module 6: checks the new article and the row filter asked for. It reads the state
# of the three instances, never a script. On rpllab1: the articles of ex_pubCatalog are exactly
# Course.Category, Course.Course, Course.CourseLanguage and Course.Session; the article Session
# has a filter procedure (sp_articlefilter: a clause given to sp_addarticle alone filters the
# snapshot and not the changes); session 17622 is canceled. On rpllab2: the subscription of
# ex_catalog to CourseLanguage is active; the Distribution Agent of ex_catalog has applied the
# snapshot of Category and of Course once only (its history, "Applied script '<article>_N.pre'"),
# so that neither was copied again; the agent runs without error. On rpllab3: CourseLanguage has
# the rows of the publisher, and Session has exactly the sessions of the publisher that are not
# canceled (row count and CHECKSUM_AGG of BINARY_CHECKSUM), so that 17622 has left.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_06/check.sh     (with Podman: ENGINE=podman ./exercises/module_06/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
out1=$(sql rpllab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
USE PachadataTraining;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF OBJECT_ID(N'dbo.syspublications') IS NULL
    INSERT @r VALUES (0, N'the articles of ex_pubCatalog: the database publishes nothing'),
                     (0, N'the article Session of ex_pubCatalog has a filter procedure: the database publishes nothing');
ELSE
BEGIN
    DECLARE @arts nvarchar(400) = (SELECT STRING_AGG(OBJECT_SCHEMA_NAME(a.objid) + N'.' + OBJECT_NAME(a.objid), N', ')
                                          WITHIN GROUP (ORDER BY OBJECT_NAME(a.objid))
                                   FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                                   WHERE p.name = N'ex_pubCatalog');
    INSERT @r SELECT IIF(@arts = N'Course.Category, Course.Course, Course.CourseLanguage, Course.Session', 1, 0),
        CONCAT(N'the articles of ex_pubCatalog are Course.Category, Course.Course, Course.CourseLanguage, Course.Session (found: ',
               ISNULL(@arts, N'none'), N')');
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                                 WHERE p.name = N'ex_pubCatalog' AND a.objid = OBJECT_ID(N'Course.Session') AND a.filter <> 0), 1, 0),
        CONCAT(N'the article Session of ex_pubCatalog has a filter procedure, made by sp_articlefilter (filter clause found: ',
               ISNULL((SELECT CAST(a.filter_clause AS nvarchar(200)) FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                       WHERE p.name = N'ex_pubCatalog' AND a.objid = OBJECT_ID(N'Course.Session')), N'none'), N')');
END;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM Course.Session WHERE SessionId = 17622 AND StatusCode = 'CANCELED'), 1, 0),
    N'session 17622 is canceled on rpllab1 (the change asked for)';
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
out2=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF DB_ID(N'distribution') IS NULL
    INSERT @r VALUES (0, N'the subscription of ex_catalog to CourseLanguage is active: no distribution database'),
                     (0, N'the snapshot of Category was applied once to ex_catalog: no distribution database'),
                     (0, N'the snapshot of Course was applied once to ex_catalog: no distribution database'),
                     (0, N'the Distribution Agent of ex_catalog is running without error: no distribution database');
ELSE
BEGIN
    -- MSsubscriptions.status 2: active.
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSsubscriptions s
                                 JOIN distribution.dbo.MSarticles a ON a.article_id = s.article_id AND a.publication_id = s.publication_id
                                 JOIN distribution.dbo.MSpublications p ON p.publication_id = s.publication_id
                                 WHERE p.publication = N'ex_pubCatalog' AND a.article = N'CourseLanguage'
                                   AND s.subscriber_db = N'ex_catalog' AND s.status = 2), 1, 0),
        N'the subscription of ex_catalog to CourseLanguage is active (MSsubscriptions.status 2)';
    DECLARE @agent int = (SELECT TOP (1) a.id FROM distribution.dbo.MSdistribution_agents a
                          WHERE a.subscriber_db = N'ex_catalog' AND a.publication = N'ex_pubCatalog' ORDER BY a.id DESC);
    -- Each snapshot applied to the subscription runs the .pre script of each article it carries.
    DECLARE @cat int = (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history
                        WHERE agent_id = @agent AND comments LIKE N'Applied script ''Category[_]%.pre''');
    DECLARE @crs int = (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_history
                        WHERE agent_id = @agent AND comments LIKE N'Applied script ''Course[_]%.pre''');
    INSERT @r SELECT IIF(@cat = 1, 1, 0),
        CONCAT(N'the snapshot of Category was applied once to ex_catalog, not again (found: ', @cat, N')');
    INSERT @r SELECT IIF(@crs = 1, 1, 0),
        CONCAT(N'the snapshot of Course was applied once to ex_catalog, not again (found: ', @crs, N')');
    DECLARE @running int = (SELECT COUNT(*) FROM distribution.dbo.MSdistribution_agents a
                            JOIN msdb.dbo.sysjobactivity ja ON ja.job_id = CAST(a.job_id AS uniqueidentifier)
                            WHERE a.id = @agent AND ja.start_execution_date IS NOT NULL
                              AND ja.stop_execution_date IS NULL
                              AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions));
    DECLARE @last int = (SELECT TOP (1) runstatus FROM distribution.dbo.MSdistribution_history
                         WHERE agent_id = @agent ORDER BY timestamp DESC);
    -- runstatus 6 is a failure; 1 start, 2 succeed, 3 in progress, 4 idle, 5 retry.
    INSERT @r SELECT IIF(@running = 1 AND @last IN (1, 3, 4), 1, 0),
        CONCAT(N'the Distribution Agent of ex_catalog is running without error (job running: ', @running,
               N', last runstatus: ', ISNULL(CAST(@last AS nvarchar(5)), N'none'), N'; 6 is a failure)');
END;
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
# rpllab3: each table compared with rpllab1, Session with the sessions that are not canceled. The
# table is looked for first: a query that names a table that does not exist fails to compile.
out3=""
for t in CourseLanguage Session; do
    q="SET NOCOUNT ON; SELECT CONCAT(COUNT(*), ' rows, checksum ', CHECKSUM_AGG(BINARY_CHECKSUM(*))) FROM"
    where=""; label="has the rows of the publisher"
    if [ $t = Session ]; then where="WHERE StatusCode <> 'CANCELED'"; label="has the sessions of the publisher that are not canceled"; fi
    want=$(sql rpllab1 -h -1 -Q "$q PachadataTraining.Course.$t $where;" 2>&1 | sed '/^$/d')
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT CASE WHEN DB_ID(N'ex_catalog') IS NULL THEN N'FAIL ex_catalog.Course.$t: no database ex_catalog on rpllab3'
                    WHEN OBJECT_ID(N'ex_catalog.Course.$t') IS NULL THEN N'FAIL ex_catalog.Course.$t: no such table on rpllab3'
                    ELSE N'' END;" 2>&1 | sed '/^$/d')
    if [ -z "$line" ]; then
        got=$(sql rpllab3 -h -1 -Q "$q ex_catalog.Course.$t;" 2>&1 | sed '/^$/d')
        if [ "$got" = "$want" ]; then line="OK   ex_catalog.Course.$t $label ($got)"
        else line="FAIL ex_catalog.Course.$t: $got on rpllab3, $want on rpllab1 ($t ${where:-all rows})"; fi
    fi
    out3="$out3$line"$'\n'
done
out3=${out3%$'\n'}
# Three checks on rpllab1, four on rpllab2, two on rpllab3: a missing line or an error message
# is a failure, so that a check that did not run is never taken for one that passed.
fail=0
for pair in "3:$out1" "4:$out2" "2:$out3"; do
    want=${pair%%:*}; o=${pair#*:}
    echo "$o"
    got=$(echo "$o" | grep -cE '^(OK|FAIL) ')
    if [ "$got" -ne "$want" ] || echo "$o" | grep -q '^Msg '; then
        echo "FAIL $got checks out of $want ran"; fail=1
    fi
    echo "$o" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The new article and the row filter of the exercise are not complete."; exit 1; fi
echo "ex_catalog receives the course titles and only the sessions that are not canceled, and Category and Course were not copied again."
