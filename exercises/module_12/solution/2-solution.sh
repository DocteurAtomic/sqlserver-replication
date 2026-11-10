#!/usr/bin/env bash
# Exercise of module 12, the solution: copies solution/answers.csv over work/answers.csv.
# Usage: ./exercises/module_12/solution/2-solution.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
cp solution/answers.csv work/answers.csv
echo "work/answers.csv now holds the solution"
