#!/usr/bin/env bash
set -u

echo "=== STATUS ==="
./client STATUS
echo

echo "=== EVENT ==="
./client EVENT LOGIN_FAILED
echo

echo "=== INVALID ==="
printf 'NOT_A_COMMAND\n' | nc 127.0.0.1 9090
echo

echo "=== OVERSIZED ==="
./scripts/test_oversized_input.sh || true
echo
