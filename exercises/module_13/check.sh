#!/usr/bin/env bash
# Exercise of module 13: checks that no replication is left on the three instances, and that the
# data stayed. It reads the state of the instances, never a script. On each instance: no
# distribution database (sys.databases.is_distributor), no published database (is_published,
# is_merge_published), no replication job (category REPL-%), no linked or remote server other
# than the instance itself (repl_distributor, the publisher at the distributor, the subscriber),
# no login distributor_admin, no publisher registered (msdb.dbo.MSdistpublishers). On rpllab1, no
# distributor (sp_get_distributor). On rpllab3, no subscription metadata in any database
# (dbo.MSreplication_subscriptions): sys.databases.is_subscribed is not used and always 0, so it
# cannot tell a subscription database. Last, PachadataTraining is still on rpllab1 and ex_catalog
# still on rpllab3, with as many sessions as the publisher.
# Exits with 0 when everything holds, with 1 otherwise, saying what is left or missing.
# Usage: ./exercises/module_13/check.sh     (with Podman: ENGINE=podman ./exercises/module_13/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
ok() { echo "OK   $1"; }
ko() { echo "FAIL $1"; fail=1; }
list() {  # instance, query returning one name per row: the names, comma separated, or empty
    sql "$1" -h -1 -Q "SET NOCOUNT ON; $2" 2>&1 | sed '/^$/d; s/[[:space:]]*$//' | paste -sd ',' | sed 's/,/, /g'
}
none() {  # instance, what, query: the query must return no row
    local r
    r=$(list "$1" "$3")
    if [ -z "$r" ]; then ok "$1: no $2"; else ko "$1: $2 left: $r"; fi
}
for n in rpllab1 rpllab2 rpllab3; do
    none $n "distribution database" "SELECT name FROM sys.databases WHERE is_distributor = 1;"
    none $n "published database" "SELECT name FROM sys.databases WHERE is_published = 1 OR is_merge_published = 1;"
    none $n "replication job" "SELECT j.name FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id WHERE c.name LIKE N'REPL-%';"
    none $n "linked or remote server" "SELECT name FROM sys.servers WHERE server_id > 0;"
    none $n "login distributor_admin" "SELECT name FROM sys.server_principals WHERE name = N'distributor_admin';"
    none $n "publisher registered at a distributor" "IF OBJECT_ID(N'msdb.dbo.MSdistpublishers') IS NOT NULL SELECT name FROM msdb.dbo.MSdistpublishers;"
done
d=$(list rpllab1 "DECLARE @d TABLE (installed int, s sysname NULL, a int, b int, c int); INSERT @d EXEC sys.sp_get_distributor; SELECT installed FROM @d;")
if [ "$d" = 0 ]; then ok "rpllab1: no distributor (sp_get_distributor)"; else ko "rpllab1: a distributor is still set (sp_get_distributor installed: $d)"; fi
none rpllab3 "subscription metadata (dbo.MSreplication_subscriptions)" "DECLARE @q nvarchar(max) = N'';
    SELECT @q += N'IF OBJECT_ID(N''' + QUOTENAME(name) + N'.dbo.MSreplication_subscriptions'') IS NOT NULL SELECT N''' + name + N''';'
    FROM sys.databases WHERE database_id > 4 AND state_desc = N'ONLINE';
    EXEC (@q);"
want=$(list rpllab1 "SELECT COUNT(*) FROM PachadataTraining.Course.Session;")
got=$(list rpllab3 "IF DB_ID(N'ex_catalog') IS NULL SELECT N'missing' ELSE IF OBJECT_ID(N'ex_catalog.Course.Session') IS NULL SELECT N'no table Course.Session' ELSE SELECT COUNT(*) FROM ex_catalog.Course.Session;")
if [[ "$want" =~ ^[0-9]+$ ]] && [ "$got" = "$want" ]; then ok "rpllab3: ex_catalog kept, $got sessions as on rpllab1"
else ko "rpllab3: ex_catalog kept with its data (found: $got, expected: $want sessions of PachadataTraining on rpllab1)"; fi

if [ $fail -ne 0 ]; then echo "Replication is not yet removed from the lab."; exit 1; fi
echo "No replication left on the three instances, and the data of ex_catalog is still there."
