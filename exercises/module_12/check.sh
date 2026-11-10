#!/usr/bin/env bash
# Exercise of module 12: checks the answers written in exercises/module_12/work/answers.csv
# against the outputs recorded on Windows in data/windows/module_12. Each expected value is
# read from those files when check.sh runs, never from the solution. Exits with 0 when the
# ten answers hold, with 1 otherwise, saying which ones do not.
# Runs on Linux, macOS and Git Bash: it needs bash and awk only.
# Usage: ./exercises/module_12/check.sh
set -uo pipefail
cd "$(dirname "$0")"
data=../../data/windows/module_12
f=work/answers.csv
if [ ! -f "$f" ]; then
    echo "FAIL $f is missing: run exercises/module_12/1-start.sh first"; exit 1
fi
for d in reconnect_sql01.txt conflict_course_sql01.csv conflict_session_sql01.csv \
         conflict_session_sql02.csv hidden_columns_sql01.txt peer_request_sql01.txt \
         requirements_sql01.txt; do
    if [ ! -f "$data/$d" ]; then echo "FAIL $data/$d is missing"; exit 1; fi
done
# CSV exported by sqlcmd -s ",": a header line, a line of dashes, then the rows
rows() { tr -d '\r' < "$data/$1" | awk -F, 'NR > 1 && $0 !~ /^-/ && NF > 1'; }
txt() { tr -d '\r' < "$data/$1"; }
expected() {
    case $1 in
        1-conflict-error)       # the error logged by the Distribution Agent when it met the conflict
            txt reconnect_sql01.txt | awk '$1 ~ /^[0-9]+$/ && $1 >= 1000 && /conflict/ { print $1; exit }' ;;
        2-conflict-kind)        # the kind of conflict named in that error
            txt reconnect_sql01.txt | sed -n "s/.*conflict of type '\([^']*\)'.*/\1/p" | head -1 ;;
        3-originator-winner)    # the originator of the winning version of course 4, originatorid policy
            rows conflict_course_sql01.csv | awk -F, '$6 == 4 && $5 == 1 { print $3; exit }' ;;
        4-course-4-price)       # the price of that winning version
            rows conflict_course_sql01.csv | awk -F, '$6 == 4 && $5 == 1 { print $7; exit }' ;;
        5-lastwriter-seats)     # session 110, last writer wins: the seats of the winning version
            rows conflict_session_sql01.csv | awk -F, '$6 == 110 && $5 == 1 { print $7; exit }' ;;
        6-lastwriter-origin)    # and the node that wrote it
            rows conflict_session_sql01.csv | awk -F, '$6 == 110 && $5 == 1 { print $3; exit }' ;;
        7-delete-update-type-paris)  # session 121 deleted in Lyon, updated later in Paris: the type logged in Paris
            rows conflict_session_sql01.csv | awk -F, '$6 == 121 { print $4; exit }' ;;
        8-p2p-cd-id-course-4)   # the first byte of $sys_p2p_cd_id of course 4: the originator of the row in place
            txt hidden_columns_sql01.txt | awk '$1 == 4 && $3 ~ /^0x/ { print substr($3, 3, 2) + 0; exit }' ;;
        9-response-before-restart)  # the received_date of Lyon's answer while its agent was stopped
            txt peer_request_sql01.txt | awk '$2 == "SQL02" { print $4; exit }' ;;
        10-filter-error)        # the error of a row filter on a peer-to-peer article
            txt requirements_sql01.txt | awk '$1 ~ /^[0-9]+$/ && /filtering/ { print $1; exit }' ;;
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
