CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Wpedantic -g -O0
TARGETS = server client

.PHONY: all clean debug

all: $(TARGETS)

server: src/server.c
	$(CC) $(CFLAGS) -o $@ $<

client: src/client.c
	$(CC) $(CFLAGS) -o $@ $<

debug: CFLAGS += -fsanitize=address,undefined
debug: clean all

clean:
	rm -f $(TARGETS)
