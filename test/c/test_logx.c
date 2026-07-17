#include "../../c/logx_linux.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

static int failed = 0;

static void check(int cond, const char *msg) {
    if (!cond) {
        fprintf(stderr, "FAIL: %s\n", msg);
        failed = 1;
    } else {
        fprintf(stdout, "PASS: %s\n", msg);
    }
}

static void test_basic_output(void) {
    char tpl[] = "/tmp/logx_c_XXXXXX";
    int fd = mkstemp(tpl);
    close(fd);

    lx_set_log_file(tpl);
    LOGX_INFO("info msg");
    LOGX_WARN("warn msg");
    LOGX_ERROR("error msg");
    LOGX_TRACE("trace msg");
    lx_set_log_file(NULL);

    FILE *f = fopen(tpl, "r");
    char buf[4][512];
    int n = 0;
    while (n < 4 && fgets(buf[n], sizeof buf[n], f)) n++;
    fclose(f);
    unlink(tpl);

    check(n == 4, "wrote 4 log lines");
    check(strstr(buf[0], "info msg")  && strstr(buf[0], "INFO "), "INFO line");
    check(strstr(buf[1], "warn msg")  && strstr(buf[1], "WARN "), "WARN line");
    check(strstr(buf[2], "error msg") && strstr(buf[2], "ERROR"), "ERROR line");
    check(strstr(buf[3], "trace msg") && strstr(buf[3], "TRACE"), "TRACE line");
}

int main(void) {
    test_basic_output();

    check(!failed, "all C tests passed");
    return failed ? 1 : 0;
}
