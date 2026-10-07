#!/usr/bin/env bash
# q4_part1_baseline.sh -- PART 1: all BASELINE evidence for Q4 in one run.
# It builds, starts the server itself, collects the evidence, stops the server and commits.
#
# Put these in your Q4 folder (Makefile, src/, client):  q4_part1_baseline.sh, probe_current_server.py
#   chmod +x q4_part1_baseline.sh && ./q4_part1_baseline.sh
# Run it while src/server.c is still the ORIGINAL (baseline) version.
set -u
cd "$(dirname "$0")" || exit 1
E=evidence
mkdir -p "$E"

if grep -q "HARDENED VERSION" src/server.c 2>/dev/null; then
    echo "STOP: src/server.c is already the hardened version. Part 1 must run on the baseline source."
    exit 1
fi
[ -f probe_current_server.py ] || { echo "ERROR: probe_current_server.py is not in this folder"; exit 1; }
sudo -v || { echo "ERROR: sudo is needed for strace"; exit 1; }

pkill -x server 2>/dev/null; sudo pkill -x strace 2>/dev/null; sleep 0.5
if ss -ltn | grep -q ':9090 '; then echo "ERROR: port 9090 is in use by something else"; exit 1; fi

echo "=== 0. Clean old files, clean rebuild (build.txt) ==="
rm -f "$E"/{build,server-start,ss-listening,ps,fd-before,lsof-before,fd-connected,ss-connected,valid-status,valid-event,invalid-input,oversized-input,probe-baseline,strace-accept,byteorder,escape-chars}.txt
rm -f "$E"/probe-after.txt "$E"/probe-diff.txt "$E"/server-after.txt
{ make clean && make; } 2>&1 | tee "$E/build.txt"
if grep -qi "warning" "$E/build.txt"; then echo "NOTE: compiler warnings, read build.txt"; else echo "no compiler warnings"; fi

echo; echo "=== 1. Start the server (log in server-start.txt) ==="
stdbuf -oL ./server > "$E/server-start.txt" 2>&1 &
PID=$!
sleep 0.8
kill -0 "$PID" 2>/dev/null || { echo "ERROR: server did not start:"; cat "$E/server-start.txt"; exit 1; }
echo "server PID = $PID"

echo; echo "=== 2. Listening socket (ss) ==="
ss -ltnp | grep 9090 | tee "$E/ss-listening.txt"

echo; echo "=== 3. Blocked, not busy (ps) ==="
ps -o pid,stat,pcpu,wchan:24,cmd -p "$PID" | tee "$E/ps.txt"

echo; echo "=== 4. Descriptors BEFORE any client ==="
ls -l /proc/"$PID"/fd | tee "$E/fd-before.txt"
lsof -nP -p "$PID" | tee "$E/lsof-before.txt"

echo; echo "=== 5. Attach strace (records in the background) ==="
sudo strace -p "$PID" -e trace=accept,accept4,recvfrom,sendto,close -o "$E/strace-accept.txt" &
sleep 1.5

echo; echo "=== 6. Valid requests ==="
./client STATUS | tee "$E/valid-status.txt"
./client EVENT LOGIN_FAILED | tee "$E/valid-event.txt"

echo; echo "=== 7. Descriptors WHILE a client is connected (silent client held 3s) ==="
python3 -c "import socket,time; s=socket.create_connection(('127.0.0.1',9090)); time.sleep(3)" &
HOLD=$!
sleep 1
ls -l /proc/"$PID"/fd | tee "$E/fd-connected.txt"
ss -tnp | grep 9090 | tee "$E/ss-connected.txt"
wait "$HOLD" 2>/dev/null
sleep 0.5

echo; echo "=== 8. Invalid and oversized input ==="
printf 'NOT_A_COMMAND\n' | timeout 3 nc 127.0.0.1 9090 | tee "$E/invalid-input.txt"
python3 -c "print('A'*1000)" | timeout 3 nc 127.0.0.1 9090 | tee "$E/oversized-input.txt"
# If the connection was reset before nc could print the reply, say so truthfully (an empty file is not evidence).
for f in invalid-input oversized-input; do
    [ -s "$E/$f.txt" ] || echo "[no response received from the server: connection ended before a reply was delivered]" | tee "$E/$f.txt"
done

echo; echo "=== 9. Malformed-input probe (BASELINE) ==="
python3 probe_current_server.py | tee "$E/probe-baseline.txt"

echo; echo "=== 10. Byte order: host vs network (task 4.5) ==="
python3 -c "import struct;p=9090;print('9090 = 0x%04x'%p);print('host (little-endian) bytes  :',struct.pack('<H',p).hex(' '));print('network (big-endian) bytes :',struct.pack('>H',p).hex(' '))" | tee "$E/byteorder.txt"

echo; echo "=== 11. Stop strace and the server ==="
sleep 0.5
sudo pkill -INT -x strace
sleep 0.7
sudo chown "$(id -un)":"$(id -gn)" "$E/strace-accept.txt"
kill -INT "$PID" 2>/dev/null
sleep 0.5
pkill -x server 2>/dev/null

echo; echo "=== 12. Escape characters the terminal was hiding (finding P8) ==="
grep -a "received event: hi" "$E/server-start.txt" | cat -v | tee "$E/escape-chars.txt"

echo; echo "=== 13. Commit ==="
[ -d .git ] || git init
git add -A
git commit -m "Q4 baseline evidence (clean run)" || echo "(nothing new to commit)"

echo; echo "=== 14. Sanity checks ==="
ok () { if [ "$2" = "1" ]; then echo "PASS  $1"; else echo "FAIL  $1"; fi; }
ok "valid-status has STATUS OK"        "$(grep -c 'STATUS OK' "$E/valid-status.txt")"
ok "valid-event has EVENT ACCEPTED"    "$(grep -c 'EVENT ACCEPTED' "$E/valid-event.txt")"
ok "fd-connected shows fd 4 socket"    "$(grep -c ' 4 -> socket' "$E/fd-connected.txt")"
ok "strace shows accept(3 ... = 4"     "$([ "$(grep -c 'accept(3.*= 4' "$E/strace-accept.txt")" -ge 1 ] && echo 1 || echo 0)"
ok "probe-baseline has all 8 probes"   "$([ "$(grep -c '^P[0-9]' "$E/probe-baseline.txt")" -eq 8 ] && echo 1 || echo 0)"
EMPTY=$(find "$E" -type f -empty)
if [ -n "$EMPTY" ]; then echo "WARNING: empty files:"; echo "$EMPTY"; else echo "PASS  no empty evidence files"; fi
echo; echo "PART 1 DONE. Next: ./q4_part2_fix_verify.sh"
