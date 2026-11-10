# Sourced by the scripts of setup/, demos/ and exercises/: the container engine, sql(), which
# runs sqlcmd inside an instance's container (password taken from the container environment,
# SQLCMDPASSWORD, set by compose.yaml, never written on the command line), and wait_for().
# Usage, from a script:  . "$(dirname "$0")/../../setup/lib.sh"   then   sql rpllab2 < file.sql
engine=${ENGINE:-docker}
nodes="rpllab1 rpllab2 rpllab3"
# Git Bash on Windows rewrites /var/opt/... arguments without this; no effect elsewhere.
export MSYS_NO_PATHCONV=1
sql() {  # instance, then sqlcmd arguments
    local c=$1; shift
    $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -W "$@"
}
# Replication agents work on their own schedule: a script never waits a fixed time for them.
# wait_for runs a query on an instance until it returns the expected value, every second, and
# fails after the timeout, printing the last value seen.
# Usage:  wait_for rpllab3 "SELECT COUNT(*) FROM PachaCatalog.Course.Course" 514 [timeout_s]
wait_for() {
    local c=$1 q=$2 want=$3 timeout=${4:-120} got i
    for i in $(seq 1 "$timeout"); do
        got=$(sql "$c" -h -1 -Q "SET NOCOUNT ON; $q" 2>&1 | tr -d '[:space:]')
        [ "$got" = "$want" ] && return 0
        sleep 1
    done
    echo "wait_for: $c returned '$got' after ${timeout}s, expected '$want': $q" >&2
    return 1
}
