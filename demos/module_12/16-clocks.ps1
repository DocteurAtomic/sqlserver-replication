# instance: SQL01, then SQL02 (PowerShell, on each node)
# ci: skip (Windows only)
# Clip 12.2: last writer wins compares the times of two nodes, so their clocks must agree. The
# offset of this machine from the domain controller (w32tm), its time zone, and what SQL Server
# reads, local and UTC.
$ProgressPreference = 'SilentlyContinue'
w32tm /stripchart /computer:dc.pachadata.local /samples:3 /dataonly
(Get-TimeZone).Id
sqlcmd -S . -E -C -W -Q "SET NOCOUNT ON; SELECT @@SERVERNAME AS node, SYSDATETIME() AS local_time, SYSUTCDATETIME() AS utc_time;"
