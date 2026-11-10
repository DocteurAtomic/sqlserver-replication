-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only: run it after demos/module_11/17-column-sync.sql, before 20-drop-pubCentres.sql)
-- Exercise of module 11: exports the conflicts of m11_pubCentres as CSV, the files of
-- data/windows/module_11 recorded on the course lab. Run it once per file:
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 1-conflicts.sql -v PART=info -o conflicts_info.csv
--   sqlcmd -S SQL01 -d m11_pacha -E -C -I -W -s "," -i 1-conflicts.sql -v PART=session -o conflict_session.csv
SET NOCOUNT ON;
IF '$(PART)' = 'info'
    SELECT a.name AS article, i.conflict_type, i.reason_code, i.origin_datasource,
           REPLACE(i.reason_text, ',', ';') AS reason_text, CONVERT(varchar(23), i.MSrepl_create_time, 121) AS create_time
    FROM dbo.MSmerge_conflicts_info AS i JOIN dbo.sysmergearticles AS a ON a.nickname = i.tablenick
    ORDER BY i.MSrepl_create_time;
IF '$(PART)' = 'session'
    SELECT c.SessionId, c.CentreCode, c.CourseTitle, c.Room, c.Seats,
           (SELECT TOP (1) i.origin_datasource FROM dbo.MSmerge_conflicts_info AS i WHERE i.rowguid = c.rowguid ORDER BY i.MSrepl_create_time DESC) AS origin_datasource
    FROM dbo.MSmerge_conflict_m11_pubCentres_Session AS c ORDER BY c.SessionId;
