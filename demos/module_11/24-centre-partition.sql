-- instance: SQL02 (the subscriber)
-- ci: skip (Windows only: needs the subscriptions of 23-subscribe-by-centre.sql)
-- Clip 11.4: what each centre received, and the download-only Centre table refusing a change.
--   sqlcmd -S SQL02 -E -C -I -i 24-centre-partition.sql
SET NOCOUNT ON;
SELECT 'm11_lille' AS centre_db, s.CentreCode, COUNT(DISTINCT s.SessionId) AS sessions, COUNT(a.AttendanceId) AS attendance
FROM m11_lille.Training.Session AS s LEFT JOIN m11_lille.Training.Attendance AS a ON a.SessionId = s.SessionId
GROUP BY s.CentreCode
UNION ALL
SELECT 'm11_geneve', s.CentreCode, COUNT(DISTINCT s.SessionId), COUNT(a.AttendanceId)
FROM m11_geneve.Training.Session AS s LEFT JOIN m11_geneve.Training.Attendance AS a ON a.SessionId = s.SessionId
GROUP BY s.CentreCode;
SELECT HOST_NAME() AS host_name_of_this_session;
BEGIN TRY
    UPDATE m11_lille.Training.Centre SET City = 'Lille centre' WHERE CentreCode = 'LIL';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, LEFT(ERROR_MESSAGE(), 200) AS error_message;
END CATCH;
