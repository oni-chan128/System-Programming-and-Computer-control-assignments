#!/usr/bin/env python3
"""
probe_current_server.py -- Q4 Task 4.7 baseline probe for YOUR OWN server on 127.0.0.1:9090.
Run it BEFORE you change server.c (baseline), save the output, then run it again after
your improvements (verification):

    python3 probe_current_server.py | tee evidence/probe-baseline.txt
    python3 probe_current_server.py | tee evidence/probe-after.txt
"""
import socket
import time

HOST, PORT = "127.0.0.1", 9090


def go(label, payload=None, pieces=None, wait=1.0):
    s = socket.create_connection((HOST, PORT), timeout=3)
    try:
        if pieces:
            for p in pieces:
                s.sendall(p)
                time.sleep(0.3)
        else:
            s.sendall(payload)
        s.settimeout(0.3)
        data, end, err, closed = b"", time.time() + wait, None, False
        while time.time() < end:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    closed = True
                    break
                data += chunk
            except socket.timeout:
                continue
            except OSError as e:
                err = repr(e)
                break
        print(f"{label}\n    reply={data!r}\n    closed_cleanly_by_server={closed}  error={err}\n")
    finally:
        s.close()


print("=== probe of", f"{HOST}:{PORT}", "===\n")
go("P1 valid STATUS", b"STATUS\n")
go("P2 valid EVENT", b"EVENT LOGIN_FAILED\n")
go("P3 invalid command", b"NOT_A_COMMAND\n")
go("P4 oversized: 1000 x 'A'", b"A" * 1000 + b"\n")
go("P5 oversized EVENT: 'EVENT ' + 1000 x 'B'", b"EVENT " + b"B" * 1000 + b"\n")
go("P6 fragmented request: 'STA' then 'TUS\\n'", pieces=[b"STA", b"TUS\n"])
go("P7 two requests in one send: 'STATUS\\nSTATUS\\n'", b"STATUS\nSTATUS\n")
go("P8 EVENT with terminal escape characters", b"EVENT hi\x1b[31mRED\n")
