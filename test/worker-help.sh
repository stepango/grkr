#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

echo "Testing worker help flags..."

assert_help() {
  local script=$1
  local arg=$2
  local expected=$3
  local output

  if ! output=$(bash "$PROJECT_ROOT/bin/$script" "$arg"); then
    echo "FAIL: $script $arg should exit 0"
    exit 1
  fi

  case "$output" in
    *"$expected"*) ;;
    *)
      echo "FAIL: $script $arg did not print expected usage"
      echo "$output"
      exit 1
      ;;
  esac
}

for arg in --help -h help; do
  assert_help worker-refuse-issue.sh "$arg" "Usage: worker-refuse-issue.sh"
  assert_help worker-resolve-pr.sh "$arg" "Usage: worker-resolve-pr.sh"
done

echo "PASS: worker help flags exit 0 and print usage"
