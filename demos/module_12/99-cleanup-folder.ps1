# instance: SQL01 (PowerShell, as an administrator, after 99-cleanup-node.sql on both nodes)
# ci: skip (Windows only)
# Module 12, cleanup: the share and the backup folder of 00-setup-folder.ps1.
$ProgressPreference = 'SilentlyContinue'
if (Get-SmbShare -Name m12_backup -ErrorAction SilentlyContinue) { Remove-SmbShare -Name m12_backup -Force }
Remove-Item -Recurse -Force C:\m12_backup -ErrorAction SilentlyContinue
"share: " + [bool](Get-SmbShare -Name m12_backup -ErrorAction SilentlyContinue)
"folder: " + (Test-Path C:\m12_backup)
