// Tests for cpp/logx.h. Build from the project root:
//   c++ -std=c++11 -Wall -Wextra -I cpp test/cpp/test_logx.cpp -o /tmp/test_logx_cpp

// Reproduce what <windows.h> does to the global namespace, so a collision shows
// up here rather than in somebody's build.
#define ERROR 0
#define min(a, b) ((a) < (b) ? (a) : (b))

#include "logx.h"

#include <cstdio>
#include <fstream>
#include <iomanip>
#include <string>
#include <vector>

static int failed = 0;

static void check(bool cond, const char* what) {
    if (cond) {
        std::printf("PASS: %s\n", what);
    } else {
        std::printf("FAIL: %s\n", what);
        failed = 1;
    }
}

static std::vector<std::string> readLines(const std::string& path) {
    std::vector<std::string> lines;
    std::ifstream in(path.c_str());
    std::string line;
    while (std::getline(in, line)) lines.push_back(line);
    return lines;
}

static bool contains(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

// "[HH:MM:SS.mmm][" -- the prefix every record shares.
static bool hasTimestamp(const std::string& line) {
    return line.size() > 14 && line[0] == '[' && line[3] == ':' && line[6] == ':'
        && line[9] == '.' && line[13] == ']' && line[14] == '[';
}

static void testStreamAndPrintf(const std::string& path) {
    check(logx::setLogFile(path), "setLogFile succeeds");

    LOGX_TRACE << "trace msg";
    LOGX_INFO << "port " << 8080;
    LOGX_WARN << "hex " << std::hex << 255;
    LOGX_ERROR << "lost";
    LOGX_INFOF("printf port %d", 8080);
    LOGX_WARNF("memory at %.1f%%", 74.2);

    logx::setLogFile();
    std::vector<std::string> lines = readLines(path);
    std::remove(path.c_str());

    check(lines.size() == 6, "wrote one line per call");
    if (lines.size() < 6) return;

    check(hasTimestamp(lines[0]), "line starts with [HH:MM:SS.mmm][");
    check(contains(lines[0], "[TRACE]"), "TRACE label");
    check(contains(lines[1], "[INFO ]"), "INFO label is padded to 5");
    check(contains(lines[2], "[WARN ]"), "WARN label is padded to 5");
    check(contains(lines[3], "[ERROR]"), "ERROR label survives the ERROR macro");

    check(contains(lines[1], "port 8080"), "stream operator<<");
    check(contains(lines[2], "hex ff"), "std::hex manipulator");
    check(contains(lines[4], "printf port 8080"), "LOGX_INFOF applies arguments");
    check(contains(lines[5], "memory at 74.2%"), "LOGX_WARNF handles %% and floats");

    check(contains(lines[0], "test_logx.cpp:"), "reports the calling file");
    check(!contains(lines[0], "/"), "path is stripped to a base name");
    check(!contains(lines[0], "\033["), "no color escapes in a file");
}

static void testLevelFilter(const std::string& path) {
    logx::setLogFile(path);
    logx::setLevel(logx::Level::Warn);
    check(logx::getLevel() == logx::Level::Warn, "getLevel reflects setLevel");
    check(!logx::enabled(logx::Level::Info), "enabled() is false below the threshold");
    check(logx::enabled(logx::Level::Error), "enabled() is true at or above it");

    LOGX_TRACE << "hidden";
    LOGX_INFOF("hidden");
    LOGX_WARN << "shown";
    LOGX_ERRORF("shown");

    logx::setLevel(logx::Level::Off);
    LOGX_ERROR << "silenced by Off";

    logx::setLevel(logx::Level::Trace);
    logx::setLogFile();
    std::vector<std::string> lines = readLines(path);
    std::remove(path.c_str());

    check(lines.size() == 2, "only Warn and above passed the filter");
}

static void testBadPath() {
    check(!logx::setLogFile("/nonexistent-dir-xyz/app.log"),
          "setLogFile reports an unwritable path");
    logx::setLogFile();
}

int main() {
    const std::string path = "/tmp/logx_cpp_test.log";

    testStreamAndPrintf(path);
    testLevelFilter(path);
    testBadPath();

    std::printf("%s\n", failed ? "C++ tests FAILED" : "all C++ tests passed");
    return failed;
}
