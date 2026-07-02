import os
import sys
import tempfile
from io import StringIO

# Set env before importing logx
os.environ["LOG_LEVEL"] = "TRACE"
os.environ["LOG_COLOR"] = "0"

# Clear any cached import
for mod in list(sys.modules.keys()):
    if 'logx' in mod:
        del sys.modules[mod]

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../python'))
import logx


def test_basic_output():
    captured_out = StringIO()
    captured_err = StringIO()
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout, sys.stderr = captured_out, captured_err

    logx.trace("trace msg")
    logx.info("info msg")
    logx.warn("warn msg")
    logx.error("error msg")

    sys.stdout, sys.stderr = old_out, old_err
    out, err = captured_out.getvalue(), captured_err.getvalue()

    assert "TRACE" in out and "trace msg" in out, "TRACE output"
    assert "INFO" in out and "info msg" in out, "INFO output"
    assert "WARN" in out and "warn msg" in out, "WARN output"
    assert "ERROR" in err and "error msg" in err, "ERROR output"
    print("PASS: test_basic_output")


def test_file_logging():
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.log') as f:
        tmp_path = f.name

    logx.set_log_file(tmp_path)
    logx.info("file test")
    logx.set_log_file(None)

    with open(tmp_path) as f:
        content = f.read()
    os.unlink(tmp_path)

    assert "file test" in content, "file log message"
    assert "INFO" in content, "file log level"
    print("PASS: test_file_logging")


def test_level_filtering():
    # Reset module with different env
    os.environ["LOG_LEVEL"] = "ERROR"
    for mod in list(sys.modules.keys()):
        if 'logx' in mod:
            del sys.modules[mod]

    import importlib
    import logx as logx2
    importlib.reload(logx2)

    captured_out = StringIO()
    captured_err = StringIO()
    sys.stdout, sys.stderr = captured_out, captured_err

    logx2.trace("should not appear")
    logx2.info("should not appear")
    logx2.error("should appear")

    sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
    out, err = captured_out.getvalue(), captured_err.getvalue()

    assert out == "", "no stdout with LOG_LEVEL=ERROR"
    assert "should appear" in err, "ERROR message in stderr"
    print("PASS: test_level_filtering")


if __name__ == "__main__":
    test_basic_output()
    test_file_logging()
    test_level_filtering()
    print("\nAll Python tests passed")
