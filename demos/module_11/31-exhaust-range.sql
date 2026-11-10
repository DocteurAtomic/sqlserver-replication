-- instance: SQL02 (the subscriber: Lille records attendance offline, line after line)
-- ci: skip (Windows only: needs the subscriptions of 23-subscribe-by-centre.sql)
-- Clip 11.5: Lille inserts up to 250 attendance lines without synchronizing, one statement
-- each, and stops at the first refusal, which it shows.
--   sqlcmd -S SQL02 -E -C -I -i 31-exhaust-range.sql
SET NOCOUNT ON;
USE m11_lille;
SELECT name, definition FROM sys.check_constraints WHERE name LIKE N'repl[_]identity[_]range%';
SELECT IDENT_CURRENT('Training.Attendance') AS ident_current_before;
DECLARE @i int = 0, @stop bit = 0;
WHILE @i < 250 AND @stop = 0
BEGIN
    BEGIN TRY
        INSERT Training.Attendance (SessionId, TraineeName, AttendanceDate, Present)
        VALUES (1001, CONCAT('Walk-in ', @i + 1), '2026-11-18', 1);
        SET @i += 1;
    END TRY
    BEGIN CATCH
        SELECT @i AS rows_inserted, ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
        SET @stop = 1;
    END CATCH;
END;
IF @stop = 0 SELECT @i AS rows_inserted;
SELECT MIN(AttendanceId) AS first_id, MAX(AttendanceId) AS last_id
FROM Training.Attendance WHERE TraineeName LIKE 'Walk-in %';
