#!/usr/bin/env bash
# Exercise of module 1, one solution: copies solution/answers.csv over work/answers.csv.
# Other answers hold: check.sh accepts every technique that meets the need.
# Usage: ./exercises/module_01/solution/2-solution.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work
cp solution/answers.csv work/answers.csv
echo "work/answers.csv now holds the solution"
