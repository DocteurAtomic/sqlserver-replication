# instance: SQL01 (run in PowerShell as an administrator, on the publisher's machine)
# ci: skip (Windows only)
# Module 11: the snapshot folder of the module, C:\m11_repldata, writable by the SQL Server
# Agent service, under which the Snapshot and Merge Agents run. The default ReplData folder of
# the instance is writable by the Database Engine service only: the Snapshot Agent fails there
# with "Access to the path ... is denied" (measured on SQL Server 2025 CU9).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$dir = 'C:\m11_repldata'
New-Item -ItemType Directory -Force $dir | Out-Null
icacls $dir /grant 'NT SERVICE\SQLSERVERAGENT:(OI)(CI)M' | Out-Null
icacls $dir
