/* beckon-hook — Claude Code hook shim.
 * Reads the hook JSON from stdin, forwards it (plus a few environment hints) to the
 * Beckon app over a Unix socket, waits for a reply, prints the reply to stdout.
 * If Beckon is not running, exits 0 immediately with no output, so Claude Code
 * falls back to its normal behaviour. Zero dependencies, ~1 ms startup. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>

/* Blocking events (the user must answer) may wait a long time, just under Claude's 600 s default hook timeout.
 * Everything else is informational: if Beckon is slow or hung we give it a few seconds and move on. */
#define BLOCKING_TIMEOUT_MS (590 * 1000)
#define INFO_TIMEOUT_MS     (4 * 1000)
static int is_blocking_event(const char *payload) {
    const char *k = strstr(payload, "\"hook_event_name\"");
    if (!k) return 1;                                   /* unknown shape → be safe, wait */
    const char *colon = strchr(k, ':'); if (!colon) return 1;
    const char *q = strchr(colon, '"'); if (!q) return 1;
    q++;                                                /* start of the event name */
    return strncmp(q, "PermissionRequest\"", 18) == 0 || strncmp(q, "PreToolUse\"", 11) == 0 || strncmp(q, "Stop\"", 5) == 0;
}

static const char *ENV_KEYS[] = {
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "__CFBundleIdentifier", "TERM_SESSION_ID",
    "ITERM_SESSION_ID", "TMUX_PANE", "TMUX", "KITTY_WINDOW_ID", "WEZTERM_PANE", "GHOSTTY_RESOURCES_DIR",
    "VSCODE_PID", "VSCODE_IPC_HOOK_CLI", "CLAUDE_PROJECT_DIR", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN",
    "CLAUDE_CODE_ENTRYPOINT", "SSH_CONNECTION", NULL
};

static char *buf; static size_t len, cap;
static void put(const char *s, size_t n) {
    if (len + n + 1 > cap) { cap = (len + n + 1) * 2; buf = realloc(buf, cap); if (!buf) _exit(0); }
    memcpy(buf + len, s, n); len += n; buf[len] = 0;
}
static void puts_(const char *s) { put(s, strlen(s)); }
static void put_json_str(const char *s) {
    puts_("\"");
    for (; *s; s++) {
        unsigned char c = (unsigned char)*s; char tmp[8];
        switch (c) {
            case '"': puts_("\\\""); break; case '\\': puts_("\\\\"); break;
            case '\n': puts_("\\n"); break; case '\r': puts_("\\r"); break; case '\t': puts_("\\t"); break;
            default:
                if (c < 0x20) { snprintf(tmp, sizeof tmp, "\\u%04x", c); puts_(tmp); } else put((const char *)&c, 1);
        }
    }
    puts_("\"");
}

static int read_all(int fd, char **out, size_t *n) {
    size_t c = 1 << 16, l = 0; char *b = malloc(c); if (!b) return -1;
    for (;;) {
        if (l + 4096 > c) { c *= 2; b = realloc(b, c); if (!b) return -1; }
        ssize_t r = read(fd, b + l, c - l - 1);
        if (r < 0) { if (errno == EINTR) continue; break; }
        if (r == 0) break; l += (size_t)r;
    }
    b[l] = 0; *out = b; *n = l; return 0;
}

int main(void) {
    const char *home = getenv("HOME"); if (!home) return 0;
    char path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    const char *override = getenv("BECKON_SOCKET");
    if (override) snprintf(path, sizeof path, "%s", override);
    else snprintf(path, sizeof path, "%s/.beckon/beckon.sock", home);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return 0;
    struct sockaddr_un addr; memset(&addr, 0, sizeof addr); addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof addr.sun_path - 1);
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) return 0;   /* Beckon not running → passthrough */

    char *payload; size_t plen;
    if (read_all(0, &payload, &plen) < 0) return 0;
    /* trim */
    char *p = payload; while (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t') p++;
    size_t e = strlen(p); while (e && (p[e-1] == ' ' || p[e-1] == '\n' || p[e-1] == '\r' || p[e-1] == '\t')) p[--e] = 0;

    puts_("{\"v\":1,\"pid\":"); { char t[32]; snprintf(t, sizeof t, "%d", getpid()); puts_(t); }
    puts_(",\"ppid\":"); { char t[32]; snprintf(t, sizeof t, "%d", getppid()); puts_(t); }
    puts_(",\"cwd\":"); { char cwd[4096]; put_json_str(getcwd(cwd, sizeof cwd) ? cwd : ""); }
    puts_(",\"env\":{"); int first = 1;
    for (int i = 0; ENV_KEYS[i]; i++) {
        const char *v = getenv(ENV_KEYS[i]); if (!v) continue;
        if (!first) puts_(","); first = 0;
        put_json_str(ENV_KEYS[i]); puts_(":"); put_json_str(v);
    }
    puts_("},\"payload\":");
    if (e && p[0] == '{' && p[e-1] == '}') put(p, e); else put_json_str(p);
    puts_("}\n");

    /* send */
    size_t off = 0;
    while (off < len) { ssize_t w = write(fd, buf + off, len - off); if (w < 0) { if (errno == EINTR) continue; return 0; } off += (size_t)w; }
    /* NOTE: no shutdown(SHUT_WR) here — Beckon treats EOF from us as "the hook process died". */

    int timeout_ms = is_blocking_event(p) ? BLOCKING_TIMEOUT_MS : INFO_TIMEOUT_MS;

    /* wait for one reply line (or EOF) */
    char reply[1 << 16]; size_t rl = 0;
    for (;;) {
        struct pollfd pfd = { fd, POLLIN, 0 };
        int pr = poll(&pfd, 1, timeout_ms);
        if (pr <= 0) return 0;                                   /* timeout → passthrough */
        ssize_t r = read(fd, reply + rl, sizeof reply - rl - 1);
        if (r < 0) { if (errno == EINTR) continue; return 0; }
        if (r == 0) break; rl += (size_t)r; reply[rl] = 0;
        if (memchr(reply, '\n', rl) || rl >= sizeof reply - 1) break;
    }
    /* trim; an empty reply or "{}" means passthrough */
    char *q = reply; while (*q == ' ' || *q == '\n' || *q == '\r' || *q == '\t') q++;
    size_t ql = strlen(q); while (ql && (q[ql-1] == ' ' || q[ql-1] == '\n' || q[ql-1] == '\r' || q[ql-1] == '\t')) q[--ql] = 0;
    if (ql == 0 || strcmp(q, "{}") == 0) return 0;
    fwrite(q, 1, ql, stdout); fputc('\n', stdout);
    return 0;
}
