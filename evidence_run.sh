#!/usr/bin/env bash
# evidence_run.sh -- Q4 baseline evidence, one pass, no typos.
# Put this file and probe_current_server.py in the same folder as ./client (your Q4 folder).
# Before running: start the server in ANOTHER terminal pane:
#     stdbuf -oL ./server 2>&1 | tee evidence/server-start.txt
# Then here:   chmod +x evidence_run.sh && ./evidence_run.sh
set -u
cd "$(dirname "$0")" || exit 1
E=evidence
mkdir -p "$E"

PID=$(pgrep -nx server) || { echo "ERROR: server is not running. Start it in the other pane first."; exit 1; }
[ -x ./client ] || { echo "ERROR: ./client not found (run make)"; exit 1; }
[ -f probe_current_server.py ] || { echo "ERROR: probe_current_server.py is not in this folder"; exit 1; }

TRACER=$(awk '/^TracerPid/{print $2}' /proc/"$PID"/status)
if [ "$TRACER" != "0" ]; then
    echo "ERROR: another strace (PID $TRACER) is already attached to the server."
    echo "       Stop it (Ctrl+C in its pane, or: sudo pkill strace) and run again."
    exit 1
fi

sudo -v || { echo "ERROR: sudo is needed for strace"; exit 1; }

# remove old files from this script (NOT server-start.txt)
rm -f "$E"/{ss-listening,ps,fd-before,lsof-before,fd-connected,ss-connected,valid-status,valid-event,invalid-input,oversized-input,probe-baseline,strace-accept}.txt

echo "=== server PID = $PID ==="

echo; echo "=== 1. Listening socket (ss) ==="
ss -ltnp | grep 9090 | tee "$E/ss-listening.txt"

echo; echo "=== 2. Blocked, not busy (ps) ==="
ps -o pid,stat,pcpu,wchan:24,cmd -p "$PID" | tee "$E/ps.txt"

echo; echo "=== 3. Descriptors BEFORE any client ==="
ls -l /proc/"$PID"/fd | tee "$E/fd-before.txt"
lsof -nP -p "$PID" | tee "$E/lsof-before.txt"

echo; echo "=== 4. Attach strace (it records in the background) ==="
sudo strace -p "$PID" -e trace=accept,accept4,recvfrom,sendto,close -o "$E/strace-accept.txt" &
sleep 1.5

echo; echo "=== 5. Valid requests ==="
./client STATUS | tee "$E/valid-status.txt"
./client EVENT LOGIN_FAILED | tee "$E/valid-event.txt"

echo; echo "=== 6. Descriptors WHILE a client is connected (silent client held open 6s) ==="
python3 -c "import socket,time; s=socket.create_connection(('127.0.0.1',9090)); time.sleep(6)" &
sleep 1.5
ls -l /proc/"$PID"/fd | tee "$E/fd-connected.txt"
ss -tnp | grep 9090 | tee "$E/ss-connected.txt"
wait %2 2>/dev/null
sleep 0.5

echo; echo "=== 7. Invalid and oversized input ==="
printf 'NOT_A_COMMAND\n' | timeout 3 nc 127.0.0.1 9090 | tee "$E/invalid-input.txt"
python3 -c "print('A'*1000)" | timeout 3 nc 127.0.0.1 9090 | tee "$E/oversized-input.txt"

echo; echo "=== 8. Malformed-input probe ==="
python3 probe_current_server.py | tee "$E/probe-baseline.txt"

echo; echo "=== 9. Stop strace and fix file ownership ==="
sleep 0.5
sudo pkill -INT -x strace
sleep 0.7
sudo chown "$(id -un)":"$(id -gn)" "$E/strace-accept.txt"

echo; echo "=== DONE. Files in $E/ ==="
ls -l "$E"
echo
echo "--- quick sanity checks ---"
echo "valid-status.txt : $(tail -1 "$E/valid-status.txt")"
echo "valid-event.txt  : $(tail -1 "$E/valid-event.txt")"
echo "fd-connected has fd 4 : $(grep -c ' 4 -> socket' "$E/fd-connected.txt") (want 1)"
echo "strace has accept(3 .. = 4 : $(grep -c 'accept(3.*= 4' "$E/strace-accept.txt") (want 1 or more)"
