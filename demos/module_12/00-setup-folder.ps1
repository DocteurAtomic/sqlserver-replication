# instance: SQL01 (run in PowerShell as an administrator, on the machine of the first node)
# ci: skip (Windows only)
# Module 12: the backup folder of the module, C:\m12_backup, shared as \\SQL01\m12_backup. The
# Database Engine of SQL01 writes the backup there, the Database Engine of SQL02 restores it
# from the share, and the Distributor of SQL01 reads it for "initialize with backup". On the
# course lab both engines run under the managed service account PACHADATA\gMSA-SQLSVC$:
# change $engine to the account of your SQL Server service (see sys.dm_server_services).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = 'C:\m12_backup'
$engine = 'PACHADATA\gMSA-SQLSVC$'
New-Item -ItemType Directory -Force $dir | Out-Null
icacls $dir /grant "NT SERVICE\MSSQLSERVER:(OI)(CI)M" "${engine}:(OI)(CI)RX" | Out-Null
if (-not (Get-SmbShare -Name m12_backup -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name m12_backup -Path $dir -ReadAccess $engine | Out-Null
}
Get-SmbShare -Name m12_backup | Select-Object Name, Path | Format-Table -AutoSize
Get-SmbShareAccess -Name m12_backup | Select-Object AccountName, AccessRight | Format-Table -AutoSize
