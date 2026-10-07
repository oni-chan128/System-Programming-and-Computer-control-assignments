/*
 * SEC 2211 Practical Assignment 2 - Question 4
 * TCP Security Event Server  (HARDENED VERSION)
 *
 * Same service and protocol as the baseline:
 *   STATUS
 *   EVENT <message>
 *
 * Improvements over the baseline (found by probe_current_server.py):
 *   P4/P5  oversized input      -> explicit rejection, never silent truncation
 *   P6     fragmented request   -> bytes are buffered until the newline arrives
 *   P8     control characters   -> EVENT text must be printable ASCII
 *   P4/P5  connection RESET     -> shutdown(SHUT_WR) + bounded drain, then close
 *   silent client holds server  -> idle timeout (SO_RCVTIMEO)
 *
 * Design decision: ONE request per connection (as in the baseline). Anything
 * the client sends after the first newline is read and discarded, by design.
 *
 * The server still never executes operating-system commands.
 */

#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define SERVER_IP "127.0.0.1"
#define SERVER_PORT 9090
#define BACKLOG 8

#define MAX_REQUEST 256        /* longest request line, not counting '\n'   */
#define MAX_EVENT_MSG 128      /* longest EVENT message                      */
#define IDLE_TIMEOUT_SEC 5     /* drop a client that sends nothing           */
#define DRAIN_TIMEOUT_SEC 1    /* how long we wait while draining input      */
#define MAX_DRAIN 65536        /* never read more than this while draining   */

enum read_status {
    READ_OK,
    READ_TOO_LONG,
    READ_EMPTY_EOF,    /* client closed without sending anything */
    READ_PARTIAL_EOF,  /* client closed in the middle of a request */
    READ_TIMEOUT,
    READ_ERROR
};

static int send_all(int fd, const char *buf, size_t len)
{
    size_t sent = 0;

    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, 0);

        if (n < 0) {
            if (errno == EINTR)
                continue;
            return -1;
        }

        if (n == 0)
            return -1;

        sent += (size_t)n;
    }

    return 0;
}

/*
 * TCP is a byte stream, not a message stream: one recv() can return half a
 * request, or more than one. So we keep calling recv() until a newline shows
 * up, but never accept more than MAX_REQUEST bytes without one.
 *
 * line must hold MAX_REQUEST + 1 bytes. *out_len gets the line length.
 */
static enum read_status read_request(int fd, char *line, size_t *out_len)
{
    char buf[MAX_REQUEST + 1];   /* request bytes + the newline */
    size_t len = 0;

    for (;;) {
        char *nl = memchr(buf, '\n', len);

        if (nl != NULL) {
            size_t n = (size_t)(nl - buf);

            if (n > 0 && buf[n - 1] == '\r')
                n--;                           /* accept CRLF clients */

            memcpy(line, buf, n);
            line[n] = '\0';
            *out_len = n;
            return READ_OK;
        }

        if (len >= sizeof(buf))                /* full, still no newline */
            return READ_TOO_LONG;

        ssize_t r = recv(fd, buf + len, sizeof(buf) - len, 0);

        if (r > 0) {
            len += (size_t)r;
            continue;
        }

        if (r == 0)
            return (len == 0) ? READ_EMPTY_EOF : READ_PARTIAL_EOF;

        if (errno == EINTR)
            continue;

        if (errno == EAGAIN || errno == EWOULDBLOCK)
            return READ_TIMEOUT;               /* SO_RCVTIMEO expired */

        return READ_ERROR;
    }
}

/* Printable ASCII only: blocks ESC, BEL, NUL, newlines, UTF-8 tricks... */
static int is_printable_ascii(const char *s)
{
    for (; *s != '\0'; s++) {
        unsigned char c = (unsigned char)*s;
        if (c < 0x20 || c > 0x7e)
            return 0;
    }
    return 1;
}

/*
 * Closing a socket that still has unread data makes the kernel send RST
 * ("connection reset") instead of a normal FIN, and the client may lose our
 * reply. So: send FIN first, read and discard what is left (bounded), then close.
 */
static void finish_connection(int fd)
{
    char sink[512];
    size_t total = 0;
    struct timeval tv;

    tv.tv_sec = DRAIN_TIMEOUT_SEC;
    tv.tv_usec = 0;

    if (shutdown(fd, SHUT_WR) < 0)
        perror("shutdown");

    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0)
        perror("setsockopt SO_RCVTIMEO");

    while (total < MAX_DRAIN) {
        ssize_t n = recv(fd, sink, sizeof(sink), 0);

        if (n > 0) {
            total += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR)
            continue;
        break;                      /* EOF, timeout or error */
    }
}

static void reply(int fd, const char *text)
{
    if (send_all(fd, text, strlen(text)) < 0)
        perror("send");
}

static void handle_client(int client_fd)
{
    char line[MAX_REQUEST + 1];
    size_t len = 0;
    struct timeval tv;

    tv.tv_sec = IDLE_TIMEOUT_SEC;
    tv.tv_usec = 0;

    if (setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0)
        perror("setsockopt SO_RCVTIMEO");

    switch (read_request(client_fd, line, &len)) {
    case READ_OK:
        break;

    case READ_TOO_LONG:
        printf("[server] rejected: request longer than %d bytes\n", MAX_REQUEST);
        reply(client_fd, "ERROR LINE_TOO_LONG\n");
        finish_connection(client_fd);
        return;

    case READ_EMPTY_EOF:
        printf("[server] client disconnected before sending data\n");
        return;

    case READ_PARTIAL_EOF:
        printf("[server] client disconnected in the middle of a request\n");
        return;

    case READ_TIMEOUT:
        printf("[server] client idle for %d s: closing\n", IDLE_TIMEOUT_SEC);
        reply(client_fd, "ERROR TIMEOUT\n");
        finish_connection(client_fd);
        return;

    case READ_ERROR:
    default:
        perror("recv");
        return;
    }

    /* An embedded NUL byte would make strcmp() see a shorter string. */
    if (strlen(line) != len) {
        printf("[server] rejected: request contains a NUL byte\n");
        reply(client_fd, "ERROR INVALID_REQUEST\n");
        finish_connection(client_fd);
        return;
    }

    if (strcmp(line, "STATUS") == 0) {
        reply(client_fd, "STATUS OK\n");
    }
    else if (strncmp(line, "EVENT ", 6) == 0 && line[6] != '\0') {
        const char *msg = line + 6;

        if (strlen(msg) > MAX_EVENT_MSG) {
            printf("[server] rejected: event message longer than %d\n",
                   MAX_EVENT_MSG);
            reply(client_fd, "ERROR MESSAGE_TOO_LONG\n");
        }
        else if (!is_printable_ascii(msg)) {
            printf("[server] rejected: event message has non-printable characters\n");
            reply(client_fd, "ERROR INVALID_CHARACTERS\n");
        }
        else {
            printf("[server] received event: %s\n", msg);
            reply(client_fd, "EVENT ACCEPTED\n");
        }
    }
    else {
        printf("[server] rejected: unknown command\n");
        reply(client_fd, "ERROR INVALID_REQUEST\n");
    }

    finish_connection(client_fd);
}

int main(void)
{
    int listen_fd;
    int opt = 1;
    struct sockaddr_in server_addr;

    signal(SIGPIPE, SIG_IGN);

    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        close(listen_fd);
        return EXIT_FAILURE;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(SERVER_PORT);

    if (inet_pton(AF_INET, SERVER_IP, &server_addr.sin_addr) != 1) {
        fprintf(stderr, "Invalid server address\n");
        close(listen_fd);
        return EXIT_FAILURE;
    }

    if (bind(listen_fd,
             (struct sockaddr *)&server_addr,
             sizeof(server_addr)) < 0) {
        perror("bind");
        close(listen_fd);
        return EXIT_FAILURE;
    }

    if (listen(listen_fd, BACKLOG) < 0) {
        perror("listen");
        close(listen_fd);
        return EXIT_FAILURE;
    }

    printf("[server] listening on %s:%d\n", SERVER_IP, SERVER_PORT);
    printf("[server] listening FD = %d\n", listen_fd);
    printf("[server] limits: request %d bytes, event message %d bytes, idle timeout %d s\n",
           MAX_REQUEST, MAX_EVENT_MSG, IDLE_TIMEOUT_SEC);
    printf("[server] waiting in accept()...\n");

    for (;;) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        int client_fd = accept(
            listen_fd,
            (struct sockaddr *)&client_addr,
            &client_len
        );

        if (client_fd < 0) {
            if (errno == EINTR)
                continue;

            perror("accept");
            break;
        }

        char client_ip[INET_ADDRSTRLEN];

        if (inet_ntop(AF_INET,
                      &client_addr.sin_addr,
                      client_ip,
                      sizeof(client_ip)) == NULL) {
            strcpy(client_ip, "unknown");
        }

        printf("[server] accepted client FD=%d from %s:%u\n",
               client_fd,
               client_ip,
               (unsigned)ntohs(client_addr.sin_port));

        handle_client(client_fd);

        if (close(client_fd) < 0)
            perror("close");
    }

    close(listen_fd);
    return EXIT_FAILURE;
}
