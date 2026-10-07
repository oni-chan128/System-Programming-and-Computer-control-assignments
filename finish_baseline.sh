#!/usr/bin/env bash
# finish_baseline.sh -- finishes the Q4 BASELINE evidence in one go.
# Run it in your Q4 folder (the one with Makefile, src/, evidence/).
#   chmod +x finish_baseline.sh && ./finish_baseline.sh
set -u
cd "$(dirname "$0")" || exit 1
E=evidence
mkdir -p "$E"

echo "=== 1. Stop the server ==="
pkill -x server 2>/dev/null
sleep 0.5
if pgrep -x server >/dev/null; then echo "WARNING: server still running"; else echo "server stopped"; fi
if ss -ltn | grep -q ':9090 '; then echo "WARNING: port 9090 still in use"; else echo "port 9090 is free"; fi

echo; echo "=== 2. Remove stale/misleading evidence files ==="
rm -fv "$E"/probe-after.txt "$E"/probe-diff.txt "$E"/server-after.txt

echo; echo "=== 3. Clean rebuild (saved to $E/build.txt) ==="
{ make clean && make; } 2>&1 | tee "$E/build.txt"
if grep -qi "warning" "$E/build.txt"; then echo "NOTE: compiler warnings found, read build.txt"; else echo "no compiler warnings"; fi

echo; echo "=== 4. Byte order: host vs network (task 4.5) ==="
python3 -c "import struct;p=9090;print('9090 = 0x%04x'%p);print('host (little-endian) bytes  :',struct.pack('<H',p).hex(' '));print('network (big-endian) bytes :',struct.pack('>H',p).hex(' '))" | tee "$E/byteorder.txt"

echo; echo "=== 5. Escape characters that the terminal was hiding (finding P8) ==="
if [ -f "$E/server-start.txt" ]; then
    grep -a "received event: hi" "$E/server-start.txt" | cat -v | tee "$E/escape-chars.txt"
else
    echo "server-start.txt not found, skipping"
fi

echo; echo "=== 6. Commit the baseline ==="
[ -d .git ] || git init
git add -A
git commit -m "Q4 baseline evidence (clean run)" || echo "(nothing new to commit)"

echo; echo "=== 7. Final check of evidence/ ==="
ls -l "$E"
EMPTY=$(find "$E" -type f -empty)
if [ -n "$EMPTY" ]; then
    echo; echo "WARNING: empty files (not valid evidence):"; echo "$EMPTY"
else
    echo; echo "no empty evidence files"
fi
echo; echo "DONE. Baseline is saved. Next step: the fix, then probe-after."
