/*
 * snapback-poke — fire-and-forget Unix-domain poker.
 *
 * Usage: snapback-poke <type> [hook_kind]
 *   <type>       one of: attention, resume, heartbeat-ping
 *   [hook_kind]  optional token (PermissionRequest | Stop); included for attention
 *
 * Reads $SNAPBACK_BRIDGE_SOCKET; falls back to ${TMPDIR:-/tmp}/snapback-bridge.sock.
 * Writes one line: "<type>\t<hook_kind?>\n" and closes.
 * Silent on every error path. Always exits 0. The hook MUST NOT notice us.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

static void resolve_socket_path(char *out, size_t cap) {
    const char *env = getenv("SNAPBACK_BRIDGE_SOCKET");
    if (env && *env) {
        snprintf(out, cap, "%s", env);
        return;
    }
    const char *tmp = getenv("TMPDIR");
    if (!tmp || !*tmp) tmp = "/tmp";
    size_t n = strlen(tmp);
    while (n > 1 && tmp[n - 1] == '/') n--;
    snprintf(out, cap, "%.*s/snapback-bridge.sock", (int)n, tmp);
}

int main(int argc, char **argv) {
    if (argc < 2) return 0;
    const char *type = argv[1];
    const char *kind = argc >= 3 ? argv[2] : "";

    char path[512];
    resolve_socket_path(path, sizeof(path));

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 0;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (strlen(path) >= sizeof(addr.sun_path)) { close(fd); return 0; }
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return 0;
    }

    char buf[256];
    int n;
    if (kind && *kind)
        n = snprintf(buf, sizeof(buf), "%s\t%s\n", type, kind);
    else
        n = snprintf(buf, sizeof(buf), "%s\n", type);

    if (n > 0 && n < (int)sizeof(buf)) {
        ssize_t written = 0;
        while (written < n) {
            ssize_t w = write(fd, buf + written, (size_t)(n - written));
            if (w < 0) { if (errno == EINTR) continue; break; }
            written += w;
        }
    }
    shutdown(fd, SHUT_WR);
    close(fd);
    return 0;
}
