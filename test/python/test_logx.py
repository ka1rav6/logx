"""Tests for python/logx.py. Run from the project root:

    python3 test/python/test_logx.py
"""

import os
import re
import sys
import tempfile

os.environ["LOG_LEVEL"] = "TRACE"
os.environ["LOG_COLOR"] = "0"
os.environ.pop("LOG_FILE", None)
os.environ.pop("LOG_STREAM", None)

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../python"))
import logx  # noqa: E402

FAILED = []

# [HH:MM:SS.mmm][LEVEL] file:line -> message
RECORD = re.compile(r"^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\[(\w+ ?)\] ([^/\\:]+):(\d+) -> (.*)$")


def check(cond, what):
    if cond:
        print("PASS: %s" % what)
    else:
        print("FAIL: %s" % what)
        FAILED.append(what)


def capture(fn):
    """Runs fn with the log file pointed at a temp file, returns the lines."""
    handle, path = tempfile.mkstemp(suffix=".log")
    os.close(handle)
    logx.set_log_file(path)
    try:
        fn()
    finally:
        logx.set_log_file(None)
    with open(path) as f:
        lines = f.read().splitlines()
    os.remove(path)
    return lines


def test_format_and_args():
    def emit():
        logx.trace("trace msg")
        logx.info("port %d", 8080)
        logx.warn("memory at %.1f%%", 74.2)
        logx.error("lost: %s", "ECONNRESET")
        logx.info("literal 100% done")
        logx.info({"a": 1})
        logx.info("mismatched %d %d", 1)

    lines = capture(emit)
    check(len(lines) == 7, "wrote one line per call")
    if len(lines) < 7:
        return

    parsed = [RECORD.match(line) for line in lines]
    check(all(parsed), "every line matches the documented format")
    if not all(parsed):
        print("  first unparsed: %r" % next(l for l, m in zip(lines, parsed) if not m))
        return

    check(parsed[0].group(1) == "TRACE", "TRACE label")
    check(parsed[1].group(1) == "INFO ", "INFO label is padded to 5")
    check(parsed[2].group(1) == "WARN ", "WARN label is padded to 5")
    check(parsed[3].group(1) == "ERROR", "ERROR label")

    check(parsed[1].group(4) == "port 8080", "%-formatting is applied")
    check(parsed[2].group(4) == "memory at 74.2%", "%% and floats survive")
    check(parsed[3].group(4) == "lost: ECONNRESET", "%s argument")
    check(parsed[4].group(4) == "literal 100% done",
          "a lone %% with no arguments is left alone")
    check(parsed[5].group(4) == "{'a': 1}", "non-string messages are stringified")
    check("mismatched" in parsed[6].group(4),
          "a format mismatch logs instead of raising")

    check(parsed[0].group(2) == "test_logx.py", "reports the calling file")
    check("\033[" not in lines[0], "no color escapes in a file")


def test_caller_through_a_wrapper():
    def my_helper(message):
        logx.log(logx.INFO, message, depth=3)

    lines = capture(lambda: my_helper("wrapped"))
    match = RECORD.match(lines[0])
    check(match is not None and match.group(2) == "test_logx.py",
          "depth= lets a wrapper report its own caller")


def test_level_filter():
    def emit():
        logx.set_level("WARN")
        logx.trace("hidden")
        logx.info("hidden")
        logx.warn("shown")
        logx.error("shown")
        logx.set_level(logx.OFF)
        logx.error("silenced by OFF")
        logx.set_level(logx.TRACE)

    lines = capture(emit)
    check(len(lines) == 2, "only WARN and above passed the filter")
    check(logx.get_level() == logx.TRACE, "get_level reflects set_level")


def test_streams():
    """ERROR and above belong on stderr, everything else on stdout."""
    import io

    out, err = io.StringIO(), io.StringIO()
    real_out, real_err = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = out, err
    try:
        logx.info("to stdout")
        logx.error("to stderr")
    finally:
        sys.stdout, sys.stderr = real_out, real_err

    check("to stdout" in out.getvalue(), "INFO goes to stdout")
    check("to stdout" not in err.getvalue(), "INFO stays off stderr")
    check("to stderr" in err.getvalue(), "ERROR goes to stderr")
    check("to stderr" not in out.getvalue(), "ERROR stays off stdout")


def test_parse_aliases():
    check(logx._parse_level("warn", 0) == logx.WARN, "level names are case-insensitive")
    check(logx._parse_level("3", 0) == logx.ERROR, "numeric levels work")
    check(logx._parse_level("junk", logx.INFO) == logx.INFO, "unknown falls back")
    check(logx._parse_bool("YES") is True, "truthy strings parse")
    check(logx._parse_bool("off") is False, "falsy strings parse")
    check(logx._parse_bool("maybe") is None, "unrecognised booleans return None")


test_format_and_args()
test_caller_through_a_wrapper()
test_level_filter()
test_streams()
test_parse_aliases()

print("Python tests FAILED" if FAILED else "all Python tests passed")
sys.exit(1 if FAILED else 0)
