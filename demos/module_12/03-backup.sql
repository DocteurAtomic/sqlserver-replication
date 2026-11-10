-- instance: SQL01 (the first node)
-- ci: skip (Windows only: peer-to-peer replication is not supported on Linux)
-- Clip 12.1: the backup that initializes the second node, taken after the publications exist
-- (they must have allow_initialize_from_backup). The file goes to the share of
-- 00-setup-folder.ps1, where SQL02 restores it.
--   sqlcmd -S SQL01 -E -C -I -i 03-backup.sql
SET NOCOUNT ON;
BACKUP DATABASE m12_catalog TO DISK = N'C:\m12_backup\m12_catalog.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
SELECT TOP (1) bs.database_name, bs.backup_finish_date, bs.first_lsn, bs.last_lsn,
       bs.compressed_backup_size / 1024 AS compressed_kb, bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'm12_catalog' ORDER BY bs.backup_finish_date DESC;
