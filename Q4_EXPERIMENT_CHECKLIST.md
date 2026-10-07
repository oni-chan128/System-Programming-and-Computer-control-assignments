# Q4 Experiment Checklist

## A. Build
- [ ] `make`
- [ ] no compiler warnings
- [ ] save build output

## B. Server / socket lifecycle
- [ ] start `./server`
- [ ] record listening FD
- [ ] run `ss -ltnp | grep 9090`
- [ ] record server PID
- [ ] run `lsof -nP -p <PID>`

## C. Blocking
- [ ] start server with no client
- [ ] observe `accept()` waiting
- [ ] use `strace -p <PID>`
- [ ] connect with `./client STATUS`
- [ ] observe accept returning

## D. Connected descriptor
- [ ] note listening FD
- [ ] note connected client FD
- [ ] explain why they are different

## E. Byte ordering
- [ ] identify `htons(9090)` in source
- [ ] identify `ntohs()` when printing client port
- [ ] explain host vs network byte order

## F. Security testing
- [ ] valid STATUS
- [ ] valid EVENT
- [ ] invalid command
- [ ] oversized input
- [ ] record actual behaviour

## G. Defence
Be able to explain:
- [ ] socket()
- [ ] bind()
- [ ] listen()
- [ ] accept()
- [ ] connect()
- [ ] send()/recv()
- [ ] close()
- [ ] blocking
- [ ] file descriptors
- [ ] htons()/ntohs()
- [ ] input validation
- [ ] why this server is iterative
