#!/usr/bin/env bash
# Exercise of module 1: checks the choices written in exercises/module_01/work/answers.csv.
# For each of the six needs, the technique must be a code of techniques.csv, one of those
# that meet the need, and the reason must be written (20 characters at least). Where several
# techniques meet a need (writes on two sites, rows changed for the CRM), each of them is
# accepted. Exits with 0 when the six choices hold, with 1 otherwise, saying what is wrong.
# Usage: ./exercises/module_01/check.sh
set -uo pipefail
cd "$(dirname "$0")"
f=work/answers.csv
if [ ! -f "$f" ]; then
    echo "FAIL $f is missing: run exercises/module_01/1-start.sh first"; exit 1
fi
codes=$(tail -n +2 techniques.csv | cut -d';' -f1 | tr '\n' ' ')
# need, then the techniques that meet it, then why the others do not
accepted() {
    case $1 in
        1-registration-catalog)     echo "transactional" ;;
        2-finance-references)       echo "snapshot transactional" ;;
        3-reporting-whole-database) echo "availability-group" ;;
        4-analytics-in-fabric)      echo "fabric-mirroring" ;;
        5-two-sites-writing)        echo "peer-to-peer bidirectional merge" ;;
        6-crm-changed-rows)         echo "change-tracking cdc" ;;
    esac
}
hint() {
    case $1 in
        1-registration-catalog)     echo "a few tables, a few seconds behind, read only on the site" ;;
        2-finance-references)       echo "small tables, needed once a night" ;;
        3-reporting-whole-database) echo "the whole database, readable, with automatic failover" ;;
        4-analytics-in-fabric)      echo "analytics in Fabric, with no load to write" ;;
        5-two-sites-writing)        echo "writes on two sites, sent to the other one" ;;
        6-crm-changed-rows)         echo "the CRM job reads the changed rows itself" ;;
    esac
}
fail=0
needs="1-registration-catalog 2-finance-references 3-reporting-whole-database 4-analytics-in-fabric 5-two-sites-writing 6-crm-changed-rows"
for need in $needs; do
    line=$(tr -d '\r' < "$f" | grep "^$need;" | head -1)
    if [ -z "$line" ]; then echo "FAIL $need: the line is missing"; fail=1; continue; fi
    tech=$(echo "$line" | cut -d';' -f2 | tr -d ' ')
    reason=$(echo "$line" | cut -d';' -f3-)
    if [ -z "$tech" ]; then echo "FAIL $need: no technique chosen"; fail=1; continue; fi
    case " $codes " in
        *" $tech "*) ;;
        *) echo "FAIL $need: '$tech' is not a code of techniques.csv"; fail=1; continue ;;
    esac
    case " $(accepted "$need") " in
        *" $tech "*) ;;
        *) echo "FAIL $need: $tech does not meet the need ($(hint "$need"))"; fail=1; continue ;;
    esac
    if [ ${#reason} -lt 20 ]; then
        echo "FAIL $need: the reason is missing or too short (20 characters at least)"; fail=1; continue
    fi
    echo "ok   $need: $tech"
done
if [ $fail -ne 0 ]; then echo "The choices do not hold yet."; exit 1; fi
echo "The choices hold."
