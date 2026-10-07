#!/usr/bin/env bash
set -euo pipefail

HOST="127.0.0.1"
PORT="9090"

python3 - <<'PY' | nc 127.0.0.1 9090
print("A" * 1000)
PY
