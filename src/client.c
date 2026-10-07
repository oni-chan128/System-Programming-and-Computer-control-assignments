/*
 * SEC 2211 Practical Assignment 2 - Question 4
 * TCP Security Event Client
 */

#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define SERVER_IP "127.0.0.1"
#define SERVER_PORT 9090
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

int main(int argc, char *argv[])
{
    int sock_fd;
    struct sockaddr_in server_addr;
    char request[MAX_LINE];
    char response[MAX_LINE];

    if (argc < 2) {
        fprintf(stderr,
                "Usage: %s STATUS | EVENT <message>\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    if (strcmp(argv[1], "STATUS") == 0) {
        snprintf(request, sizeof(request), "STATUS\n");
    }
    else if (strcmp(argv[1], "EVENT") == 0) {
        if (argc < 3) {
            fprintf(stderr, "EVENT requires a message\n");
            return EXIT_FAILURE;
        }

        int written = snprintf(request, sizeof(request),
                               "EVENT %s\n", argv[2]);

        if (written < 0 || (size_t)written >= sizeof(request)) {
            fprintf(stderr, "Event message is too long\n");
            return EXIT_FAILURE;
        }
    }
    else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        return EXIT_FAILURE;
    }

    sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(SERVER_PORT);

    if (inet_pton(AF_INET, SERVER_IP, &server_addr.sin_addr) != 1) {
        fprintf(stderr, "Invalid server address\n");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    /*
     * connect() establishes the TCP connection to the server.
     */
    if (connect(sock_fd,
                (struct sockaddr *)&server_addr,
                sizeof(server_addr)) < 0) {
        perror("connect");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    printf("[client] connected, FD=%d\n", sock_fd);

    if (send_all(sock_fd, request, strlen(request)) < 0) {
        perror("send");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    ssize_t n = recv(sock_fd, response, sizeof(response) - 1, 0);

    if (n < 0) {
        perror("recv");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    response[n] = '\0';
    printf("[client] server response: %s", response);

    if (close(sock_fd) < 0) {
        perror("close");
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
