# Module 12, peer-to-peer replication (Windows only)

SQL Server on Linux does not support peer-to-peer replication, and it needs the Enterprise
edition (Developer will do for a lab): these scripts do not run on the course lab, and
`setup/run-scripts.sh` skips them (`ci: skip`). They were recorded on two SQL Server 2025 CU9
instances for Windows in an Active Directory domain, the two nodes of the topology: `SQL01`
(Paris) and `SQL02` (Lyon). Each node is its own distributor (`m12_distribution`), as Learn
recommends for peer-to-peer. The outputs are in `data/windows/module_12`, and the exercise
uses them.

Every object the scripts create starts with `m12_`: the database `m12_catalog` on both nodes
(the same name is required), the publications `m12_pubCourse` and `m12_pubSession`, the
distribution databases, the backup folder `C:\m12_backup` shared as `\\SQL01\m12_backup`.
Plus one login on each node: the computer account of the other node (`PACHADATA\SQL01$` and
`PACHADATA\SQL02$` on the course lab), under which the SQL Server Agent service account
`NT Service\SQLSERVERAGENT` reaches the network, and under which the push Distribution Agent of
that node connects. Change `PEER_LOGIN`, `PEER` and, in `00-setup-folder.ps1`, the account of
the Database Engine service to your own names.

Run them in the order of their numbers, each on the instance named in its first line, with
`sqlcmd -S <instance> -E -C -I -i <file>` and the `-v` variables its header gives:

| Scripts | Instance | Clip |
|---|---|---|
| `00-setup-folder.ps1` (PowerShell, as an administrator) | SQL01 | 12.1 |
| `00-setup-node.sql` (`-v PEER_LOGIN="PACHADATA\SQL02$"`, then on SQL02 `PACHADATA\SQL01$`) | both | 12.1 |
| `01-create-catalog.sql` (`-v PEER_LOGIN="PACHADATA\SQL02$"`), `02-publish.sql` (`-v ORIGINATOR_ID=1`), `03-backup.sql` | SQL01 | 12.1 |
| `04-restore.sql` (`-v PEER_LOGIN="PACHADATA\SQL01$"`), `02-publish.sql` (`-v ORIGINATOR_ID=2`) | SQL02 | 12.1 |
| `05-subscribe-from-backup.sql` (`-v PEER=SQL02`) | SQL01 | 12.1 |
| `06-subscribe-support-only.sql` (`-v PEER=SQL01`) | SQL02 | 12.1 |
| `07-paris-insert.sql`, then `08-lyon-read-insert.sql` on SQL02, then `09-paris-read.sql`, `09b-requirements.sql` | SQL01, SQL02 | 12.1 |
| `10-cut-paris.sql` on SQL01, `11-cut-lyon.sql` on SQL02, `12-reconnect.sql` on SQL01 then SQL02 | both | 12.2 |
| `13-continue-onconflict.sql`, `14-restart-course.sql`, `15-continue-off.sql`, each on SQL01 then SQL02 | both | 12.2 |
| `16-clocks.ps1` (PowerShell), on SQL01 then SQL02 | both | 12.2 |
| `17-cut-lyon-sessions.sql` on SQL02, `18-cut-paris-sessions.sql` on SQL01, `19-reconnect-sessions.sql` on SQL01 then SQL02 | both | 12.2 |
| `20-hidden-columns.sql`, through the dedicated administrator connection (`sqlcmd -S SQL01 -A ...`) | SQL01 | 12.2 |
| `21-lyon-stops.sql` on SQL02, `22-request-response.sql` on SQL01, `23-lyon-restarts.sql` on SQL02, `24-read-responses.sql` on SQL01 | both | 12.3 |
| `99-cleanup-node.sql` on SQL01 then SQL02 (`-v PEER_LOGIN=...`), then `99-cleanup-folder.ps1` on SQL01 | both | |

`07` to `09`, `12`, `14`, `19`, `22` and `24` wait for a row, an agent or an answer in a
bounded loop (one minute at most, 30 seconds for `22`), never for a fixed delay. The export of
the exercise (`exercises/module_12/export`) runs after `24`, before the cleanup.
