#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
export PATH="$PROJECT_ROOT/bin:$PATH"

echo "Testing worker-resolve-pr.sh shell interface..."

if [ ! -f "$PROJECT_ROOT/bin/worker-resolve-pr.sh" ]; then
    echo "FAIL: worker-resolve-pr.sh not found"
    exit 1
fi

if [ ! -x "$PROJECT_ROOT/bin/worker-resolve-pr.sh" ]; then
    echo "FAIL: worker-resolve-pr.sh not executable"
    exit 1
fi

echo "PASS: worker-resolve-pr.sh exists and is executable"

echo "Testing error handling for missing arguments..."
if "$PROJECT_ROOT/bin/worker-resolve-pr.sh" 2>/dev/null; then
    echo "FAIL: Should exit with error when no PR number provided"
    exit 1
fi

echo "PASS: Correctly errors on missing PR number"

echo "Testing error handling for invalid PR number..."
if "$PROJECT_ROOT/bin/worker-resolve-pr.sh" "invalid" 2>/dev/null; then
    echo "FAIL: Should exit with error for invalid PR number"
    exit 1
fi

echo "PASS: Correctly errors on invalid PR number"

echo "Testing PR number format validation..."
for num in "123" "1" "999999"; do
    output=$("$PROJECT_ROOT/bin/worker-resolve-pr.sh" "$num" 2>&1 || true)
    if echo "$output" | grep -q "Invalid PR number"; then
        echo "FAIL: Should accept valid PR number: $num"
        exit 1
    fi
    if echo "$output" | grep -q "Usage:"; then
        echo "FAIL: Should accept valid PR number: $num"
        exit 1
    fi
done

echo "PASS: Accepts valid PR number formats"

echo "All shell compatibility tests passed!"
