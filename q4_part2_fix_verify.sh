#!/usr/bin/env bash
# q4_part2_fix_verify.sh -- PART 2: install the hardened server, repeat the tests, compare, verify.
#
# Put these in your Q4 folder:  q4_part2_fix_verify.sh, server_fixed.c, probe_current_server.py
#   chmod +x q4_part2_fix_verify.sh && ./q4_part2_fix_verify.sh
# Needs the baseline from Part 1 (evidence/probe-baseline.txt).
set -u
cd "$(dirname "$0")" || exit 1
E=evidence
mkdir -p "$E"

[ -s "$E/probe-baseline.txt" ] || { echo "ERROR: evidence/probe-baseline.txt is missing or empty. Run Part 1 first."; exit 1; }
[ -f probe_current_server.py ] || { echo "ERROR: probe_current_server.py is not in this folder"; exit 1; }
[ -f server_fixed.c ] || grep -q "HARDENED VERSION" src/server.c 2>/dev/null || { echo "ERROR: server_fixed.c is not in this folder"; exit 1; }

pkill -x server 2>/dev/null; sleep 0.5
if ss -ltn | grep -q ':9090 '; then echo "ERROR: port 9090 is in use by something else"; exit 1; fi

echo "=== 1. Save the baseline source in Git, then install the fix ==="
[ -d .git ] || git init
git add -A
git commit -m "Q4 snapshot before hardening" || echo "(nothing new to commit)"
if grep -q "HARDENED VERSION" src/server.c; then
    echo "src/server.c is already the hardened version"
else
    cp server_fixed.c src/server.c
    echo "installed server_fixed.c as src/server.c"
fi

echo; echo "=== 2. Clean rebuild (build-after.txt) ==="
{ make clean && make; } 2>&1 | tee "$E/build-after.txt"
if grep -qi "warning" "$E/build-after.txt"; then echo "NOTE: compiler warnings, read build-after.txt"; else echo "no compiler warnings"; fi
[ -x ./server ] || { echo "ERROR: build failed"; exit 1; }

echo; echo "=== 3. Start the hardened server (log in server-after.txt) ==="
rm -f "$E"/{server-after,valid-status-after,valid-event-after,invalid-input-after,oversized-input-after,probe-after,probe-diff,timeout-test}.txt
stdbuf -oL ./server > "$E/server-after.txt" 2>&1 &
PID=$!
sleep 0.8
kill -0 "$PID" 2>/dev/null || { echo "ERROR: server did not start:"; cat "$E/server-after.txt"; exit 1; }
echo "server PID = $PID"
ss -ltnp | grep 9090

echo; echo "=== 4. Valid requests still work ==="
./client STATUS | tee "$E/valid-status-after.txt"
./client EVENT LOGIN_FAILED | tee "$E/valid-event-after.txt"

echo; echo "=== 5. Invalid and oversized input (after) ==="
printf 'NOT_A_COMMAND\n' | timeout 3 nc 127.0.0.1 9090 | tee "$E/invalid-input-after.txt"
python3 -c "print('A'*1000)" | timeout 3 nc 127.0.0.1 9090 | tee "$E/oversized-input-after.txt"
for f in invalid-input-after oversized-input-after; do
    [ -s "$E/$f.txt" ] || echo "[no response received from the server: connection ended before a reply was delivered]" | tee "$E/$f.txt"
done

echo; echo "=== 6. Malformed-input probe (AFTER) ==="
python3 probe_current_server.py | tee "$E/probe-after.txt"

echo; echo "=== 7. Silent client: is it dropped? (about 5 seconds) ==="
python3 - <<'EOF' | tee "$E/timeout-test.txt"
import socket, time
s = socket.create_connection(("127.0.0.1", 9090))
s.settimeout(15)
t0 = time.time()
data = s.recv(100)
waited = time.time() - t0
eof = (s.recv(100) == b"")
print(f"silent client was answered after {waited:.1f}s with {data!r}; connection then closed cleanly: {eof}")
EOF

echo; echo "=== 8. Before vs after (probe-diff.txt) ==="
diff -u "$E/probe-baseline.txt" "$E/probe-after.txt" > "$E/probe-diff.txt"
cat "$E/probe-diff.txt"

echo; echo "=== 9. Stop the server ==="
kill -INT "$PID" 2>/dev/null
sleep 0.5
pkill -x server 2>/dev/null

echo; echo "=== 10. Verification checks ==="
blk () { awk -v p="$1" '$1==p{f=1;next} /^P[0-9]/{f=0} f' "$E/probe-after.txt"; }
ok () { if [ "$2" = "1" ]; then echo "PASS  $1"; else echo "FAIL  $1"; fi; }
yes_if () { if eval "$1"; then echo 1; else echo 0; fi; }
ok "P1/P2 valid requests still work"                 "$(yes_if 'blk P1 | grep -q "STATUS OK" && blk P2 | grep -q "EVENT ACCEPTED"')"
ok "P4 oversized line rejected, clean close (no reset)" "$(yes_if 'blk P4 | grep -q LINE_TOO_LONG && blk P4 | grep -q "closed_cleanly_by_server=True"')"
ok "P5 oversized EVENT rejected (no silent truncation)" "$(yes_if 'blk P5 | grep -q LINE_TOO_LONG && ! blk P5 | grep -q ACCEPTED')"
ok "P6 fragmented request handled correctly"         "$(yes_if 'blk P6 | grep -q "STATUS OK"')"
ok "P7 one request per connection (by design)"       "$(yes_if '[ "$(blk P7 | grep -o "STATUS OK" | wc -l)" -eq 1 ]')"
ok "P8 control characters rejected"                  "$(yes_if 'blk P8 | grep -q INVALID_CHARACTERS')"
ok "silent client dropped by timeout"                "$(yes_if 'grep -q "ERROR TIMEOUT" "$E/timeout-test.txt"')"

echo; echo "=== 11. Commit ==="
git add -A
git commit -m "Q4 harden input handling and verify" || echo "(nothing new to commit)"

echo; echo "=== 12. Files ==="
ls -l "$E"
EMPTY=$(find "$E" -type f -empty)
if [ -n "$EMPTY" ]; then echo "WARNING: empty files:"; echo "$EMPTY"; else echo "no empty evidence files"; fi
echo; echo "PART 2 DONE. Q4 practical work is complete. Next: report + presentation."
