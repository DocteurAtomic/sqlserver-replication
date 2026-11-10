-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run it after demos/module_11/33-insert-again.sql)
-- Exercise of module 11: exports the merge sessions, the identity ranges and the partitions of
-- m11_pubByCentre as CSV. Run it once per file:
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 2-merge.sql -v PART=sessions -o merge_sessions.csv
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 2-merge.sql -v PART=ranges -o identity_ranges.csv
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 2-merge.sql -v PART=partitions -o partition_groups.csv
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 2-merge.sql -v PART=articles -o articles.csv
SET NOCOUNT ON;
IF '$(PART)' = 'sessions'
    SELECT ROW_NUMBER() OVER (PARTITION BY a.publication, a.subscriber_db ORDER BY s.session_id) AS sync_number,
           a.publication, a.subscriber_db,
           CASE s.runstatus WHEN 2 THEN 'succeeded' WHEN 6 THEN 'failed' ELSE CONVERT(varchar(10), s.runstatus) END AS result,
           s.upload_inserts, s.upload_updates, s.upload_deletes, s.upload_conflicts,
           s.download_inserts, s.download_updates, s.download_deletes, s.download_conflicts
    FROM m11_distribution.dbo.MSmerge_sessions AS s
    JOIN m11_distribution.dbo.MSmerge_agents AS a ON a.id = s.agent_id
    WHERE s.runstatus IN (2, 6)
    ORDER BY a.publication, a.subscriber_db, s.session_id;
IF '$(PART)' = 'ranges'
    SELECT s.db_name AS node, r.range_begin, r.range_end, r.next_range_begin, r.next_range_end
    FROM dbo.MSmerge_identity_range AS r
    JOIN dbo.sysmergesubscriptions AS s ON s.subid = r.subid
    WHERE r.is_pub_range = 0 ORDER BY r.range_begin;
IF '$(PART)' = 'partitions'
    SELECT s.db_name AS subscriber_db, g.partition_id, g.HOST_NAME_FN AS host_name_value
    FROM dbo.MSmerge_partition_groups AS g
    JOIN dbo.sysmergesubscriptions AS s ON s.partition_id = g.partition_id
    ORDER BY g.partition_id;
IF '$(PART)' = 'articles'
    SELECT p.name AS publication, a.name AS article, a.column_tracking, a.upload_options,
           a.identity_support, REPLACE(CONVERT(nvarchar(400), a.subset_filterclause), ',', ';') AS subset_filterclause
    FROM dbo.sysmergearticles AS a JOIN dbo.sysmergepublications AS p ON p.pubid = a.pubid
    ORDER BY p.name, a.name;
