-- instance: SQL01, then SQL02 (each node exports its own tables)
-- ci: skip (Windows only: run it after demos/module_12/24-read-responses.sql, before 99-cleanup-node.sql)
-- Exercise of module 12: exports the conflict tables and the publications of one node as CSV,
-- the files of data/windows/module_12 recorded on the course lab. Run it once per file and node:
--   sqlcmd -S SQL01 -d m12_catalog -E -C -I -W -s "," -i 1-export.sql -v PART=course -o conflict_course_sql01.csv
--   sqlcmd -S SQL01 -d m12_catalog -E -C -I -W -s "," -i 1-export.sql -v PART=session -o conflict_session_sql01.csv
--   sqlcmd -S SQL01 -d m12_catalog -E -C -I -W -s "," -i 1-export.sql -v PART=publications -o publications_sql01.csv
-- and the same three on SQL02, with _sql02 in the file names.
SET NOCOUNT ON;
IF '$(PART)' = 'course'
    SELECT @@SERVERNAME AS node, __$originator_id AS originator_id, __$origin_datasource AS origin,
           __$conflict_type AS conflict_type, __$is_winner AS is_winner, CourseId, Price,
           REPLACE(__$reason_text, ',', ';') AS reason_text
    FROM dbo.conflict_Catalog_Course ORDER BY __$row_id;
IF '$(PART)' = 'session'
    SELECT @@SERVERNAME AS node, __$originator_id AS originator_id, __$origin_datasource AS origin,
           __$conflict_type AS conflict_type, __$is_winner AS is_winner, SessionId, Seats,
           CONVERT(varchar(27), __$sys_mw_cd_id, 121) AS last_write_utc,
           REPLACE(__$reason_text, ',', ';') AS reason_text
    FROM dbo.conflict_Catalog_Session ORDER BY SessionId, __$row_id;
IF '$(PART)' = 'publications'
    SELECT @@SERVERNAME AS node, p.name AS publication, o.originator_id,
           CASE WHEN p.options & 256 = 256 THEN 'lastwriter' ELSE 'originatorid' END AS conflict_policy,
           (p.options & 16) / 16 AS continue_onconflict, a.name AS article
    FROM dbo.syspublications AS p
    JOIN dbo.sysarticles AS a ON a.pubid = p.pubid
    JOIN dbo.MSpeer_originatorid_history AS o
      ON o.originator_publication = p.name AND o.originator_node = @@SERVERNAME
    ORDER BY p.name;
