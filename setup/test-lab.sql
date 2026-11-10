-- Run by test-lab.sh on each instance, with the variable N set to the instance name.
-- One row per check: OK or FAIL, then the check.
SET NOCOUNT ON;
DECLARE @c TABLE (n int IDENTITY, chk nvarchar(200), ok bit);
INSERT @c SELECT N'server name is $(N)', IIF(@@SERVERNAME = N'$(N)', 1, 0);
INSERT @c SELECT N'SQL Server 2025 (17.x)', IIF(CAST(SERVERPROPERTY('ProductMajorVersion') AS int) = 17, 1, 0);
INSERT @c SELECT N'SQL Server Agent running',
    IIF(EXISTS (SELECT * FROM sys.dm_exec_sessions WHERE program_name LIKE N'SQLAgent%'), 1, 0);
-- compose.yaml gives 3 GB to the distributor, 2 GB to the two others.
INSERT @c SELECT CONCAT(N'memory seen by the instance at most ', IIF(@@SERVERNAME = N'rpllab2', 3, 2), N' GB'),
    IIF((SELECT physical_memory_kb FROM sys.dm_os_sys_info) <= IIF(@@SERVERNAME = N'rpllab2', 3, 2) * 1024 * 1024, 1, 0);
INSERT @c SELECT N'snapshot folder /var/opt/mssql/share/repldata present',
    IIF(EXISTS (SELECT * FROM sys.dm_os_file_exists(N'/var/opt/mssql/share/repldata')
                WHERE file_is_a_directory = 1), 1, 0);
IF @@SERVERNAME = N'rpllab1'
    INSERT @c SELECT N'PachadataTraining online, full recovery model',
        IIF(EXISTS (SELECT * FROM sys.databases WHERE name = N'PachadataTraining'
                    AND state_desc = N'ONLINE' AND recovery_model_desc = N'FULL'), 1, 0);
SELECT CONCAT(IIF(ok = 1, N'OK   ', N'FAIL '), N'$(N): ', chk) FROM @c ORDER BY n;
