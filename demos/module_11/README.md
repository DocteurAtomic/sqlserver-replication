# Module 11, merge replication (Windows only)

SQL Server on Linux does not support merge replication: these scripts do not run on the
course lab, and `setup/run-scripts.sh` skips them (`ci: skip`). They were recorded on two
SQL Server 2025 CU9 instances for Windows in an Active Directory domain: `SQL01`, the
publisher and its own distributor (`m11_distribution`), and `SQL02`, which holds the two
subscription databases of the centres, `m11_lille` and `m11_geneve`. The outputs are in
`data/windows/module_11`, and the exercise uses them.

Every object the scripts create starts with `m11_` (databases, publications, distribution
database, snapshot folder `C:\m11_repldata`), plus one login on the subscriber: the computer
account of the publisher (`PACHADATA\SQL01$` on the course lab), under which the SQL Server
Agent service account `NT Service\SQLSERVERAGENT` reaches the network. Change
`AGENT_LOGIN` and `SUBSCRIBER` to your own names. With a single instance, give its own name
to `SUBSCRIBER` and skip `AGENT_LOGIN`.

Run them in the order of their numbers, each on the instance named in its first line, with
`sqlcmd -S <instance> -E -C -I -i <file>` and the `-v` variables its header gives:

| Scripts | Instance | Clip |
|---|---|---|
| `00-setup-folder.ps1` (PowerShell, as an administrator), `00-setup-publisher.sql` | SQL01 | 11.1 |
| `00-setup-subscriber.sql` (`-v AGENT_LOGIN="PACHADATA\SQL01$"`) | SQL02 | 11.1 |
| `01-publish.sql`, `02-snapshot.sql`, `02b-what-changed.sql` | SQL01 | 11.1 |
| `03-subscribe.sql` (`-v SUBSCRIBER=SQL02`), `04-first-sync.sql` | SQL01 | 11.2 |
| `04b-first-sync-centre.sql`, `05-roundtrip-centre.sql` | SQL02 | 11.2 |
| `06-roundtrip-sync.sql` | SQL01 | 11.2 |
| `07-roundtrip-check.sql` | SQL02 | 11.2 |
| `08`, `10`, `12`, `14`, `16` on SQL02, `09`, `11`, `13`, `15`, `17` on SQL01, alternately | both | 11.3 |
| after `15-column-tracking.sql`: `02-snapshot.sql` and `04-first-sync.sql` again, before `16` | SQL01 | 11.3 |
| `20` to `23` (`23` with `-v SUBSCRIBER=SQL02`), `25`, `28` on SQL01; `24`, `26`, `27` on SQL02 | both | 11.4 |
| `30`, `32` on SQL01; `31`, `33` on SQL02 | both | 11.5 |
| `99-cleanup-publisher.sql`, then `99-cleanup-subscriber.sql` (`-v AGENT_LOGIN=...`), then delete `C:\m11_repldata` | both | |

The exports of the exercise (`exercises/module_11/export`) run after `17` for the conflicts
and after `33` for the rest.
