#!/usr/bin/env bash
# Exercise of module 3: checks the snapshot publication asked for. It reads the state of the
# three instances, never a script. On rpllab1: a snapshot publication ex_pubRef, active, whose
# articles are exactly Reference.Currency, Reference.PaymentMethod and Reference.Holiday. On
# rpllab2: its Snapshot Agent and the Distribution Agent of the subscription to ex_ref each
# scheduled once a day (daily, not every few minutes), and a snapshot applied to ex_ref. On
# rpllab3: the three tables in ex_ref, with as many rows as on rpllab1.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_03/check.sh     (with Podman: ENGINE=podman ./exercises/module_03/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tables="Currency PaymentMethod Holiday"
out1=$(sql rpllab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
USE PachadataTraining;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF OBJECT_ID(N'dbo.syspublications') IS NULL
    INSERT @r VALUES (0, N'a snapshot publication ex_pubRef in PachadataTraining: the database publishes nothing'),
                     (0, N'ex_pubRef is active'),
                     (0, N'the articles of ex_pubRef are Reference.Currency, Reference.PaymentMethod, Reference.Holiday');
ELSE
BEGIN
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM dbo.syspublications WHERE name = N'ex_pubRef' AND repl_freq = 1), 1, 0),
        N'a snapshot publication ex_pubRef in PachadataTraining (@repl_freq = snapshot)';
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM dbo.syspublications WHERE name = N'ex_pubRef' AND status = 1), 1, 0),
        N'ex_pubRef is active (@status)';
    DECLARE @arts nvarchar(400) = (SELECT STRING_AGG(OBJECT_SCHEMA_NAME(a.objid) + N'.' + OBJECT_NAME(a.objid), N', ')
                                          WITHIN GROUP (ORDER BY OBJECT_NAME(a.objid))
                                   FROM dbo.sysarticles a JOIN dbo.syspublications p ON p.pubid = a.pubid
                                   WHERE p.name = N'ex_pubRef');
    INSERT @r SELECT IIF(@arts = N'Reference.Currency, Reference.Holiday, Reference.PaymentMethod', 1, 0),
        CONCAT(N'the articles of ex_pubRef are Reference.Currency, Reference.PaymentMethod, Reference.Holiday (found: ',
               ISNULL(@arts, N'none'), N')');
END;
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
out2=$(sql rpllab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, ok bit, line nvarchar(400));
IF DB_ID(N'distribution') IS NULL
    INSERT @r VALUES (0, N'the Snapshot Agent of ex_pubRef runs once a day: no distribution database'),
                     (0, N'the Distribution Agent of ex_ref runs once a day: no distribution database'),
                     (0, N'a snapshot applied to ex_ref: no distribution database');
ELSE
BEGIN
    -- freq_type 4 is daily, freq_subday_type 1 once in the day (2, 4 and 8 repeat it every
    -- so many seconds, minutes or hours).
    INSERT @r SELECT ISNULL(MAX(IIF(s.freq_type = 4 AND s.freq_subday_type = 1, 1, 0)), 0),
        CONCAT(N'the Snapshot Agent of ex_pubRef runs once a day (freq_type ', ISNULL(CAST(MAX(s.freq_type) AS nvarchar(5)), N'none'),
               N', freq_subday_type ', ISNULL(CAST(MAX(s.freq_subday_type) AS nvarchar(5)), N'none'), N'; 4 and 1 expected)')
    FROM distribution.dbo.MSsnapshot_agents a
    JOIN msdb.dbo.sysjobschedules js ON js.job_id = CAST(a.job_id AS uniqueidentifier)
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE a.publication = N'ex_pubRef';
    INSERT @r SELECT ISNULL(MAX(IIF(s.freq_type = 4 AND s.freq_subday_type = 1, 1, 0)), 0),
        CONCAT(N'the Distribution Agent of ex_ref runs once a day (freq_type ', ISNULL(CAST(MAX(s.freq_type) AS nvarchar(5)), N'none'),
               N', freq_subday_type ', ISNULL(CAST(MAX(s.freq_subday_type) AS nvarchar(5)), N'none'), N'; 4 and 1 expected)')
    FROM distribution.dbo.MSdistribution_agents a
    JOIN msdb.dbo.sysjobschedules js ON js.job_id = CAST(a.job_id AS uniqueidentifier)
    JOIN msdb.dbo.sysschedules s ON s.schedule_id = js.schedule_id
    WHERE a.subscriber_db = N'ex_ref';
    INSERT @r SELECT IIF(EXISTS (SELECT * FROM distribution.dbo.MSdistribution_history h
                                 JOIN distribution.dbo.MSdistribution_agents a ON a.id = h.agent_id
                                 WHERE a.subscriber_db = N'ex_ref' AND h.runstatus = 2
                                   AND h.comments LIKE N'Applied the snapshot%'), 1, 0),
        N'a snapshot applied to ex_ref (MSdistribution_history: "Applied the snapshot to the Subscriber.")';
END;
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), line) FROM @r ORDER BY n;
SQL
)
# The rows: counted on rpllab1, then compared on rpllab3.
out3=""
for t in $tables; do
    want=$(sql rpllab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM PachadataTraining.Reference.$t;" 2>&1 | tr -d '[:space:]')
    line=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON;
        SELECT CASE WHEN DB_ID(N'ex_ref') IS NULL THEN N'FAIL ex_ref.Reference.$t: no database ex_ref on rpllab3'
                    WHEN OBJECT_ID(N'ex_ref.Reference.$t') IS NULL THEN N'FAIL ex_ref.Reference.$t: no such table on rpllab3'
                    ELSE N'' END;" 2>&1 | sed '/^$/d')
    if [ -z "$line" ]; then
        got=$(sql rpllab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM ex_ref.Reference.$t;" 2>&1 | tr -d '[:space:]')
        if [ "$got" = "$want" ]; then line="OK   ex_ref.Reference.$t has the $want rows of the publisher"
        else line="FAIL ex_ref.Reference.$t has $got rows, $want on the publisher"; fi
    fi
    out3="$out3$line"$'\n'
done
out3=${out3%$'\n'}
# Three checks on rpllab1, three on rpllab2, three on rpllab3: a missing line or an error
# message is a failure, so that a check that did not run is never taken for one that passed.
fail=0
for pair in "3:$out1" "3:$out2" "3:$out3"; do
    want=${pair%%:*}; o=${pair#*:}
    echo "$o"
    got=$(echo "$o" | grep -cE '^(OK|FAIL) ')
    if [ "$got" -ne "$want" ] || echo "$o" | grep -q '^Msg '; then
        echo "FAIL $got checks out of $want ran"; fail=1
    fi
    echo "$o" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The snapshot publication of the exercise is not complete."; exit 1; fi
echo "ex_pubRef delivers its three tables to ex_ref, once a night."
