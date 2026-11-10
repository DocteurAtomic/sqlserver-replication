#!/usr/bin/env bash
# Exercise of module 1: writes the starting state, work/answers.csv, a copy of
# answers-template.csv with the six needs and empty choices. An existing answers file is kept
# as work/answers.csv.bak before it is replaced. Nothing is written on the lab.
# Usage: ./exercises/module_01/1-start.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work
if [ -f work/answers.csv ] && ! cmp -s work/answers.csv answers-template.csv; then
    cp work/answers.csv work/answers.csv.bak
    echo "Your previous answers are kept in exercises/module_01/work/answers.csv.bak"
fi
cp answers-template.csv work/answers.csv
echo "Write your choices in exercises/module_01/work/answers.csv, then run check.sh"
