#!/usr/bin/env bash
# Exercise of module 10: checks the security asked by the audit. It reads the state of the three
# instances, never a script. On rpllab2, in the distribution database: the Log Reader Agent of
# PachadataTraining, the Snapshot Agent of ex_pubCatalog and the Distribution Agent of
# ex_catalog connect with SQL Server logins, none of them sa, two different logins for the
# Log Reader and the Snapshot Agents, a stored password for each. On rpllab1: the two logins
# exist, belong to no server role, and are db_owner of PachadataTraining; the Log Reader Agent
# runs connected with its login; ex_reporting is no longer in the PAL of ex_pubCatalog. On
# rpllab3: the login of the Distribution Agent exists, belongs to no server role, is db_owner
# of ex_catalog, and the agent runs connected with it. Last, a change: the description of the
# category EX is changed on rpllab1 and must arrive on rpllab3 within two minutes.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_10/check.sh     (with Podman: ENGINE=podman ./exercises/module_10/check.sh)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
ok() { echo "OK   $1"; }
ko() { echo "FAIL $1"; fail=1; }
val() {  # one value from an instance, empty when the query fails
    sql "$1" -h -1 -Q "SET NOCOUNT ON; $2" 2>/dev/null | sed '/^$/d' | head -1 | sed 's/[[:space:]]*$//'
}

# rpllab2: the connections stored for the three agents (mode|login|password bytes).
lr=$(val rpllab2 "IF DB_ID(N'distribution') IS NOT NULL SELECT TOP (1) CONCAT(publisher_security_mode, N'|', publisher_login, N'|', ISNULL(DATALENGTH(publisher_password), 0))
                  FROM distribution.dbo.MSlogreader_agents WHERE publisher_db = N'PachadataTraining';")
sn=$(val rpllab2 "IF DB_ID(N'distribution') IS NOT NULL SELECT TOP (1) CONCAT(publisher_security_mode, N'|', publisher_login, N'|', ISNULL(DATALENGTH(publisher_password), 0))
                  FROM distribution.dbo.MSsnapshot_agents WHERE publication = N'ex_pubCatalog';")
da=$(val rpllab2 "IF DB_ID(N'distribution') IS NOT NULL SELECT TOP (1) CONCAT(subscriber_security_mode, N'|', subscriber_login, N'|', ISNULL(DATALENGTH(subscriber_password), 0))
                  FROM distribution.dbo.MSdistribution_agents WHERE subscriber_db = N'ex_catalog';")
login() { echo "$1" | cut -d'|' -f2; }
agent() {  # name, stored connection: SQL Server login, not sa, a password
    local name=$1 c=$2 l
    l=$(login "$c")
    if [ -z "$c" ]; then ko "$name: no such agent on rpllab2"; return; fi
    if [ "${c%%|*}" = 0 ] && [ -n "$l" ] && [ "$l" != sa ] && [ "${c##*|}" -gt 0 ]; then
        ok "$name connects with its own SQL Server login ($l)"
    else
        ko "$name connects with a dedicated SQL Server login, not sa, with its password (found: mode ${c%%|*}, login '${l}', password ${c##*|} bytes)"
    fi
}
agent "the Log Reader Agent of PachadataTraining, to rpllab1" "$lr"
agent "the Snapshot Agent of ex_pubCatalog, to rpllab1" "$sn"
agent "the Distribution Agent of ex_catalog, to rpllab3" "$da"
L1=$(login "$lr"); L2=$(login "$sn"); L3=$(login "$da")
if [ -n "$L1" ] && [ "$L1" != "$L2" ]; then ok "one login per agent on rpllab1 ($L1, $L2)"
else ko "one login per agent on rpllab1: the Log Reader and the Snapshot Agents share '$L1'"; fi

rights() {  # instance, login, database: the login exists, no server role, db_owner of the database
    local n=$1 l=$2 db=$3 r
    [ -z "$l" ] || [ "$l" = sa ] && { ko "$n: least privilege in $db, not checked: the agent has no dedicated login yet ('$l')"; return; }
    r=$(val $n "SELECT CONCAT(
            IIF(SUSER_ID(N'$l') IS NULL, N'missing', N'exists'), N'|',
            (SELECT COUNT(*) FROM sys.server_role_members m JOIN sys.server_principals p ON p.principal_id = m.member_principal_id WHERE p.name = N'$l'), N'|',
            IIF(DB_ID(N'$db') IS NULL, 0, (SELECT COUNT(*) FROM [$db].sys.database_role_members rm
                JOIN [$db].sys.database_principals r ON r.principal_id = rm.role_principal_id
                JOIN [$db].sys.database_principals u ON u.principal_id = rm.member_principal_id
                WHERE r.name = N'db_owner' AND u.sid = SUSER_SID(N'$l'))));")
    if [ "$r" = "exists|0|1" ]; then ok "$n: $l belongs to no server role and is db_owner of $db"
    else ko "$n: $l exists, belongs to no server role (sysadmin included) and is db_owner of $db (found: $r; exists|0|1 expected)"; fi
}
rights rpllab1 "$L1" PachadataTraining
rights rpllab1 "$L2" PachadataTraining
rights rpllab3 "$L3" ex_catalog

# The new connections are taken when the agents start again.
s=$(val rpllab1 "SELECT ISNULL(STRING_AGG(login_name, N','), N'none') FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%-PachadataTraining-%';")
if [ -n "$L1" ] && [ "$s" = "$L1" ]; then ok "rpllab1: the Log Reader Agent runs connected as $L1"
else ko "rpllab1: the Log Reader Agent runs connected with its login (found: $s); restart its job"; fi
s=$(val rpllab3 "SELECT ISNULL(STRING_AGG(login_name, N','), N'none') FROM (SELECT DISTINCT login_name FROM sys.dm_exec_sessions
                  WHERE program_name = N'rpllab1_PachadataTraining_ex_pubCatalog' AND DB_NAME(database_id) = N'ex_catalog') d;")
if [ -n "$L3" ] && [ "$s" = "$L3" ]; then ok "rpllab3: the Distribution Agent runs connected as $L3"
else ko "rpllab3: the Distribution Agent runs connected with its login (found: $s); restart its job"; fi

# sp_help_publication_access fills a table by INSERT ... EXEC itself, so it cannot be nested in
# another one (Msg 8164): its result is read as text, one login per line.
pal=$(sql rpllab1 -d PachadataTraining -h -1 -s '|' -Q "SET NOCOUNT ON;
    EXEC sys.sp_help_publication_access @publication = N'ex_pubCatalog';" 2>/dev/null \
    | cut -d'|' -f1 | sed '/^$/d' | LC_ALL=C sort | paste -sd ',' | sed 's/,/, /g' || true)
[ -n "$pal" ] || pal="no publication"
case ", $pal," in
    *", ex_reporting,"*) ko "rpllab1: ex_reporting is still in the PAL of ex_pubCatalog (PAL: $pal)" ;;
    *"no publication"*|*"Msg "*|", ,") ko "rpllab1: the PAL of ex_pubCatalog could not be read ($pal)" ;;
    *) ok "rpllab1: the PAL of ex_pubCatalog is $pal" ;;
esac

# A change on the publisher, which must still reach the subscriber.
stamp="checked at $(date -u +%H:%M:%S)"
n=$(val rpllab1 "UPDATE PachadataTraining.Course.Category SET Description = '$stamp' WHERE CategoryCode = 'EX'; SELECT @@ROWCOUNT;")
if [ "$n" != 1 ]; then ko "rpllab1: the category EX to change (run 1-start.sh)"
elif wait_for rpllab3 "SELECT COUNT(*) FROM ex_catalog.Course.Category WHERE CategoryCode = 'EX' AND Description = '$stamp'" 1 120 2>/dev/null; then
    ok "rpllab3: a change made on rpllab1 arrived ($stamp)"
else ko "rpllab3: a change made on rpllab1 arrives within two minutes (description '$stamp' of the category EX)"; fi

if [ $fail -ne 0 ]; then echo "The agents of the exercise are not yet as the audit asks."; exit 1; fi
echo "The agents of ex_pubCatalog connect with their own logins, at least privilege, and the catalog still arrives."
