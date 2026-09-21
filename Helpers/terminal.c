// Native PTY bridge: first-run setup must not require Python or Xcode.
#include <util.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static volatile sig_atomic_t stopping = 0;
static void stop(int sig) { (void)sig; stopping = 1; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int write_all(int fd, const char *p, ssize_t n) {
    while (n > 0) { ssize_t k = write(fd, p, n); if (k < 0) { if (errno == EINTR) continue; return -1; } p += k; n -= k; } return 0;
}
int main(int argc, char **argv) {
    if (argc < 2) return 2;
    int master; struct winsize size = {32,120,0,0};
    pid_t child = forkpty(&master, NULL, NULL, &size);
    if (child < 0) { perror("forkpty"); return 1; }
    if (child == 0) {
        struct termios settings;
        if (tcgetattr(0, &settings) == 0) { settings.c_lflag &= ~ECHO; tcsetattr(0, TCSANOW, &settings); }
        setenv("TERM", "dumb", 1); execvp(argv[1], argv + 1); perror("execvp"); _exit(127);
    }
    signal(SIGTERM, stop); signal(SIGINT, stop); signal(SIGPIPE, SIG_IGN);
    double deadline = 0; int status = 0; int input_open = 1; int output_open = 1; int reaped = 0;
    while (output_open || !reaped) {
        if (stopping && deadline == 0) { kill(-child, SIGTERM); deadline = now() + 2; }
        if (deadline && now() >= deadline) { kill(-child, SIGKILL); if (!reaped) waitpid(child, &status, 0); break; }
        if (!reaped && waitpid(child, &status, WNOHANG) == child) { reaped = 1; if (!deadline) deadline = now() + 2; }
        fd_set reads; FD_ZERO(&reads); if (output_open) FD_SET(master, &reads); if (input_open) FD_SET(0, &reads);
        struct timeval tv = {0,100000};
        int result = select(master + 1, &reads, NULL, NULL, &tv);
        if (result < 0) { if (errno == EINTR) continue; stopping = 1; continue; }
        char buf[65536]; ssize_t n;
        if (output_open && FD_ISSET(master, &reads)) {
            n = read(master, buf, sizeof(buf));
            if (n <= 0) { output_open = 0; if (!reaped) stopping = 1; }
            else if (write_all(1, buf, n) < 0) stopping = 1;
        }
        if (input_open && FD_ISSET(0, &reads)) {
            n = read(0, buf, sizeof(buf));
            if (n <= 0) { input_open = 0; stopping = 1; }
            else if (write_all(master, buf, n) < 0) stopping = 1;
        }
    }
    close(master);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
