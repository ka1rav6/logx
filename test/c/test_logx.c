/* Tests for c/logx.h. Build from the project root:
 *   cc -std=c99 -Wall -Wextra -I c test/c/test_logx.c -o /tmp/test_logx_c
 */
#include "logx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failed = 0;

static void check(int cond, const char *what) {
    if (cond) {
        printf("PASS: %s\n", what);
    } else {
        printf("FAIL: %s\n", what);
        failed = 1;
    }
}

/* Reads a log file into `lines`, returning how many were read. */
static int read_lines(const char *path, char lines[][512], int max) {
    FILE *f = fopen(path, "r");
    int n = 0;
    if (!f) return 0;
    while (n < max && fgets(lines[n], 512, f)) n++;
    fclose(f);
    return n;
}

/* "[HH:MM:SS.mmm][" -- the prefix every record shares. */
static int has_timestamp(const char *line) {
    return line[0] == '[' && line[3] == ':' && line[6] == ':' && line[9] == '.'
        && line[13] == ']' && line[14] == '[';
}

static void test_format_and_levels(const char *path) {
    char lines[8][512];
    int n;

    check(lx_set_log_file(path) == 0, "lx_set_log_file succeeds");

    LOGX_TRACE("trace msg");
    LOGX_INFO("port %d", 8080);
    LOGX_WARN("memory at %.1f%%", 74.2);
    LOGX_ERROR("lost: %s", "ECONNRESET");
    LOGX_INFO("literal 100%% done");

    lx_set_log_file(NULL);
    n = read_lines(path, lines, 8);
    remove(path);

    check(n == 5, "wrote one line per call");
    if (n < 5) return;

    check(has_timestamp(lines[0]), "line starts with [HH:MM:SS.mmm][");
    check(strstr(lines[0], "[TRACE]") != NULL, "TRACE label");
    check(strstr(lines[1], "[INFO ]") != NULL, "INFO label is padded to 5");
    check(strstr(lines[2], "[WARN ]") != NULL, "WARN label is padded to 5");
    check(strstr(lines[3], "[ERROR]") != NULL, "ERROR label");

    check(strstr(lines[1], "port 8080") != NULL, "printf arguments are applied");
    check(strstr(lines[2], "memory at 74.2%") != NULL, "%% and floats survive");
    check(strstr(lines[3], "lost: ECONNRESET") != NULL, "%s argument");
    check(strstr(lines[4], "literal 100% done") != NULL, "escaped %% renders as one %");

    /* The file name must be this test file, not logx.h, and never a full path. */
    check(strstr(lines[0], "test_logx.c:") != NULL, "reports the calling file");
    check(strstr(lines[0], "/") == NULL, "path is stripped to a base name");

    check(strstr(lines[0], "\033[") == NULL, "no color escapes in a file");
}

static void test_level_filter(const char *path) {
    char lines[8][512];
    int n;

    lx_set_log_file(path);
    lx_set_level(LX_WARN);
    check(lx_get_level() == LX_WARN, "lx_get_level reflects lx_set_level");

    LOGX_TRACE("hidden");
    LOGX_INFO("hidden");
    LOGX_WARN("shown");
    LOGX_ERROR("shown");

    lx_set_level(LX_OFF);
    LOGX_ERROR("silenced by OFF");

    lx_set_level(LX_TRACE);
    lx_set_log_file(NULL);
    n = read_lines(path, lines, 8);
    remove(path);

    check(n == 2, "only WARN and above passed the filter");
    if (n == 2) {
        check(strstr(lines[0], "shown") != NULL, "WARN passed");
        check(strstr(lines[1], "shown") != NULL, "ERROR passed");
    }
}

static void test_bad_path(void) {
    check(lx_set_log_file("/nonexistent-dir-xyz/app.log") == -1,
          "lx_set_log_file reports an unwritable path");
}

int main(void) {
    char path[256];
    snprintf(path, sizeof path, "/tmp/logx_c_test_%ld.log", (long)getpid());

    test_format_and_levels(path);
    test_level_filter(path);
    test_bad_path();

    printf("%s\n", failed ? "C tests FAILED" : "all C tests passed");
    return failed;
}
