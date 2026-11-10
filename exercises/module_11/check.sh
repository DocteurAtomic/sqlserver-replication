#!/usr/bin/env bash
# Exercise of module 11: checks the answers written in exercises/module_11/work/answers.csv
# against the outputs recorded on Windows in data/windows/module_11. Each expected value is
# read from those files when check.sh runs, never from the solution. Exits with 0 when the
# ten answers hold, with 1 otherwise, saying which ones do not.
# Runs on Linux, macOS and Git Bash: it needs bash and awk only.
# Usage: ./exercises/module_11/check.sh
set -uo pipefail
cd "$(dirname "$0")"
data=../../data/windows/module_11
f=work/answers.csv
if [ ! -f "$f" ]; then
    echo "FAIL $f is missing: run exercises/module_11/1-start.sh first"; exit 1
fi
for d in conflicts_info.csv conflict_session.csv merge_sessions.csv identity_ranges.csv \
         partition_groups.csv exhaust_range.txt centre_partition.txt; do
    if [ ! -f "$data/$d" ]; then echo "FAIL $data/$d is missing"; exit 1; fi
done
# CSV exported by sqlcmd -s ",": a header line, a line of dashes, then the rows
rows() { tr -d '\r' < "$data/$1" | awk -F, 'NR > 1 && $0 !~ /^-/ && NF > 1'; }
expected() {
    case $1 in
        1-row-conflict-winner)  # the data source the resolver chose in the first update conflict
            rows conflicts_info.csv | awk -F, '$2 == 1 { print; exit }' \
                | sed -n "s/.*chose the update from '\([^']*\)'.*/\1/p" ;;
        2-lost-seats-1002)      # the losing version of session 1002, kept in the conflict table
            rows conflict_session.csv | awk -F, '$1 == 1002 { print $5; exit }' ;;
        3-insert-conflict-types)  # the conflict types logged for the primary key violation
            rows conflicts_info.csv | awk -F, '$3 == 2627 { print $2 }' | sort -u | tr '\n' ' ' | sed 's/ $//' ;;
        4-late-column-tracking-type)  # the type of the last conflict, after column tracking was switched on
            rows conflicts_info.csv | tail -1 | cut -d, -f2 ;;
        5-lille-first-download)  # rows downloaded by the first synchronization of Lille
            rows merge_sessions.csv | awk -F, '$3 == "m11_lille" && $1 == 1 { print $9 }' ;;
        6-move-deletes-lille)    # rows deleted at Lille by its second synchronization
            rows merge_sessions.csv | awk -F, '$3 == "m11_lille" && $1 == 2 { print $11 }' ;;
        7-lille-host-name)
            rows partition_groups.csv | awk -F, '$1 == "m11_lille" { print $3 }' ;;
        8-rows-before-548)
            tr -d '\r' < "$data/exhaust_range.txt" | awk '$2 == 548 { print $1; exit }' ;;
        9-lille-new-range)
            rows identity_ranges.csv | awk -F, '$1 == "m11_lille" { print $2 }' ;;
        10-download-only-error)
            tr -d '\r' < "$data/centre_partition.txt" | awk '$1 ~ /^[0-9]+$/ && $2 == "Table" { print $1; exit }' ;;
    esac
}
fail=0
questions=$(tail -n +2 answers-template.csv | tr -d '\r' | cut -d';' -f1)
for q in $questions; do
    want=$(expected "$q")
    if [ -z "$want" ]; then echo "FAIL $q: no expected value found in $data"; fail=1; continue; fi
    line=$(tr -d '\r' < "$f" | grep "^$q;" | head -1)
    got=$(echo "$line" | cut -d';' -f2- | sed 's/^ *//; s/ *$//')
    if [ -z "$got" ]; then echo "FAIL $q: no answer"; fail=1; continue; fi
    if [ "$(echo "$got" | tr '[:upper:]' '[:lower:]')" != "$(echo "$want" | tr '[:upper:]' '[:lower:]')" ]; then
        echo "FAIL $q: '$got' is not what the outputs show"; fail=1; continue
    fi
    echo "ok   $q"
done
if [ $fail -ne 0 ]; then echo "The answers do not hold yet."; exit 1; fi
echo "The answers hold."
