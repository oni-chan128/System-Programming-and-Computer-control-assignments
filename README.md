# SEC 2211 Practical Assignment 2 — Question 4

## Build and Secure a TCP Client/Server Application

This laboratory implementation is intentionally small and designed for the Week 2
Q4 requirements. It runs on localhost and provides a controlled security-event
service.

**Important:** Run this only on your own Linux machine/VM or another explicitly
authorized laboratory environment.

## 1. Service design

The server listens on:

- Address: `127.0.0.1`
- Port: `9090`
- Protocol: TCP
- Service commands:
  - `STATUS`
  - `EVENT <message>`

Example flow:

```text
TCP Client
   |
   | connect()
   v
Listening Server
   |
   | accept()
   v
Connected Client FD
   |
   | recv()
   v
Request validation
   |
   +--> STATUS -> STATUS OK
   |
   +--> EVENT  -> EVENT ACCEPTED
   |
   +--> invalid -> ERROR INVALID_REQUEST
```

The server is intentionally iterative: it handles one connected client before
returning to `accept()`.

## 2. Build

```bash
make
```

The compiler uses:

```text
-Wall -Wextra -Wpedantic -g -O0
```

These options make warnings visible and keep debugging information available.

## 3. Run

Terminal 1:

```bash
./server
```

Expected:

```text
[server] listening on 127.0.0.1:9090
[server] listening FD = 3
[server] waiting in accept()...
```

Terminal 2:

```bash
./client STATUS
```

Then:

```bash
./client EVENT LOGIN_FAILED
```

## 4. Question 4 mapping

### 4.1 Server

The server uses:

```text
socket()
bind()
listen()
accept()
recv()
send()
close()
```

### 4.2 Client

The client uses:

```text
socket()
connect()
send()
recv()
close()
```

### 4.3 Socket descriptors

`socket()` returns the listening descriptor.

`accept()` returns a NEW descriptor for the connected client.

The original listening descriptor remains available so the server can accept
future connections.

### 4.4 Blocking

The server is expected to remain waiting at:

```c
accept(...)
```

when no client is connected.

Use:

```bash
strace -p <SERVER_PID>
```

to observe the server while it is waiting.

Then connect using:

```bash
./client STATUS
```

The system call returns and the server proceeds.

### 4.5 Byte ordering

The code uses:

```c
htons(SERVER_PORT)
```

because the port is a 16-bit integer that must be represented in network byte
order for socket addressing.

The server uses:

```c
ntohs(client_port)
```

when displaying the client's port.

### 4.6 Observation tools

Useful commands:

```bash
ps -ef | grep ./server
pstree -p <SERVER_PID>
ss -ltnp | grep 9090
lsof -nP -p <SERVER_PID>
strace -p <SERVER_PID>
```

While a client is connected, also inspect:

```bash
ss -tnp | grep 9090
```

### 4.7 Security testing

Valid:

```bash
./client STATUS
./client EVENT LOGIN_SUCCESS
```

Invalid command:

```bash
printf 'BADCOMMAND\n' | nc 127.0.0.1 9090
```

The expected response is:

```text
ERROR INVALID_REQUEST
```

For oversized input, use the supplied script:

```bash
./scripts/test_oversized_input.sh
```

The server uses a bounded receive buffer and rejects input that does not match
the defined application protocol.

## 5. Engineering notes

This implementation deliberately does NOT execute operating-system commands
received from clients. The assignment explicitly prohibits arbitrary operating
system command execution.

The application protocol is intentionally small:

```text
STATUS
EVENT <message>
```

Anything else is rejected.

## 6. Evidence to collect

Do not fabricate evidence. Run the commands and save your actual output.

Recommended evidence:

1. Successful build.
2. Server showing listening FD.
3. `ss` showing port 9090.
4. `ps`/`pstree` identifying the server.
5. `strace` showing `accept()`.
6. Client connection and server's new connected FD.
7. Successful STATUS request.
8. Successful EVENT request.
9. Invalid request and rejection.
10. Oversized input behaviour.
11. Before/after explanation of the input-handling improvement.

Suggested directory:

```text
evidence/
├── build.txt
├── server.txt
├── ss-listening.txt
├── ps.txt
├── strace-accept.txt
├── valid-client.txt
├── invalid-client.txt
└── oversized-input.txt
```

## 7. Presentation defence questions

Every group member should be able to answer:

1. What does `socket()` return?
2. Why does `bind()` happen before `listen()`?
3. What does `listen()` do?
4. Why does `accept()` return another FD?
5. What happens to the listening FD after `accept()`?
6. Why can `accept()` block?
7. What makes this different from an uncontrolled busy loop?
8. What does `connect()` do?
9. Why do we use `htons()`?
10. What happens if the client sends an invalid request?
11. How did you test oversized input?
12. What Linux tool proves that port 9090 is listening?
13. What Linux tool can show the server's open descriptors?
14. What does `strace` show when the server is waiting?
15. What resource needs to be closed?
16. What would happen if the server did not validate input?
17. Why is this server iterative rather than multi-client?
18. How would a future Week 3 design improve concurrent client handling?

## 8. Important limitation

This is a Week 2 Q4 implementation. It is deliberately an iterative server.
The multi-client/event-driven redesign belongs to Question 6 in Week 3.

The purpose here is to investigate the basic TCP lifecycle, descriptors,
blocking, byte order, Linux observation and application-level input handling.
