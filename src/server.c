/*
 * SEC 2211 Practical Assignment 2 - Question 4
 * TCP Security Event Server
 *
 * Lab-only service:
 *   - listens on 127.0.0.1:9090
 *   - accepts one client at a time
 *   - supports STATUS and EVENT <text>
 *   - deliberately contains a simple, bounded application protocol
 *
 * Q4 investigations:
 *   4.1 TCP socket lifecycle
 *   4.2 Client/server communication
 *   4.3 listening FD vs connected FD
 *   4.4 blocking at accept()
 *   4.5 network byte order
 *   4.6 Linux observation tools
 *   4.7 malformed/oversized input and mitigation
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
#include <unistd.h>

#define SERVER_IP "127.0.0.1"
#define SERVER_PORT 9090
#define BACKLOG 8
#define MAX_LINE 256

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

static void handle_client(int client_fd)
{
    char buffer[MAX_LINE];
    ssize_t n;

    n = recv(client_fd, buffer, sizeof(buffer) - 1, 0);

    if (n < 0) {
        perror("recv");
        return;
    }

    if (n == 0) {
        printf("[server] client disconnected before sending data\n");
        return;
    }

    buffer[n] = '\0';

    /* Remove one trailing newline for simple command parsing. */
    buffer[strcspn(buffer, "\r\n")] = '\0';

    if (strcmp(buffer, "STATUS") == 0) {
        const char *response = "STATUS OK\n";
        if (send_all(client_fd, response, strlen(response)) < 0)
            perror("send");
    }
    else if (strncmp(buffer, "EVENT ", 6) == 0 && buffer[6] != '\0') {
        printf("[server] received event: %s\n", buffer + 6);

        const char *response = "EVENT ACCEPTED\n";
        if (send_all(client_fd, response, strlen(response)) < 0)
            perror("send");
    }
    else {
        const char *response = "ERROR INVALID_REQUEST\n";
        if (send_all(client_fd, response, strlen(response)) < 0)
            perror("send");
    }
}

int main(void)
{
    int listen_fd;
    int opt = 1;
    struct sockaddr_in server_addr;

    signal(SIGPIPE, SIG_IGN);

    /*
     * socket() creates the listening socket.
     * AF_INET  = IPv4
     * SOCK_STREAM = TCP
     */
    listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    /*
     * Allow quick restart after the server is stopped.
     * This is a socket option, not an application-level security bypass.
     */
    if (setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        close(listen_fd);
        return EXIT_FAILURE;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;

    /*
     * htons() converts the 16-bit port from host byte order
     * to network byte order.
     */
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
    printf("[server] waiting in accept()...\n");

    for (;;) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        /*
         * accept() blocks here when there is no pending connection.
         * It returns a NEW descriptor for the connected client.
         * listen_fd remains the listening socket.
         */
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
