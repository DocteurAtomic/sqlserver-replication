-- instance: SQL01 (Paris), through the dedicated administrator connection
-- ci: skip (Windows only)
-- Clip 12.2: the hidden columns that conflict detection reads. They exist only through the
-- dedicated administrator connection (-A); a normal connection gets Msg 126. Course has
-- $sys_p2p_cd_id (originator and version), Session has it too, plus the time of the last
-- write of last writer wins. The name $sys_md_cd_id, given by one Learn page, does not exist.
--   sqlcmd -S SQL01 -A -E -C -I -i 20-hidden-columns.sql
SET NOCOUNT ON;
USE m12_catalog;
SELECT CourseId, Price, $sys_p2p_cd_id AS p2p_cd_id FROM Catalog.Course WHERE CourseId IN (1, 4, 11, 12) ORDER BY CourseId;
SELECT SessionId, Seats, $sys_p2p_cd_id AS p2p_cd_id, $sys_mw_cd_id AS mw_cd_id
FROM Catalog.Session WHERE SessionId IN (101, 110, 141, 142) ORDER BY SessionId;
BEGIN TRY
    EXEC (N'SELECT TOP (1) $sys_md_cd_id FROM Catalog.Session;');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
