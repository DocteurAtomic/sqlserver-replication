#!/usr/bin/env bash
# Exercise of module 12: writes the starting state, work/answers.csv, a copy of
# answers-template.csv with the ten questions and empty answers. An existing answers file is
# kept as work/answers.csv.bak before it is replaced. Nothing is written on the lab: the
# exercise reads the outputs recorded on Windows in data/windows/module_12.
# Usage: ./exercises/module_12/1-start.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work
if [ -f work/answers.csv ] && ! cmp -s work/answers.csv answers-template.csv; then
    cp work/answers.csv work/answers.csv.bak
    echo "Your previous answers are kept in exercises/module_12/work/answers.csv.bak"
fi
cp answers-template.csv work/answers.csv
echo "Write your answers in exercises/module_12/work/answers.csv, then run check.sh"
