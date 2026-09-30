"""
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
"""

# logx -- single-file logger for Python 3.8+. Linux, macOS, Windows.
#
#     from logx import info, warn, error
#
#     info("listening on port %d", 8080)
#     warn("memory at %.1f%%", 74.2)
#     error("connection lost")
#
# Arguments are applied with %-formatting, and only when the level actually
# passes the filter, so a filtered-out call costs almost nothing.
#
# Environment
#   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
#   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
#   NO_COLOR    set to anything to disable color (https://no-color.org)
#   LOG_FILE    path to append to instead of writing to the terminal
#   LOG_STREAM  split (default) | stdout | stderr

import os
import sys
import threading
import time

__all__ = [
    "TRACE", "INFO", "WARN", "ERROR", "FATAL", "OFF",
    "trace", "info", "warn", "error", "fatal", "log",
    "set_level", "get_level", "set_log_file", "set_color", "flush",
]

__version__ = "1.1.0"

TRACE = 0
INFO = 1
WARN = 2
ERROR = 3
FATAL = 4
OFF = 5

_NAMES = ("TRACE", "INFO ", "WARN ", "ERROR", "FATAL")
_COLORS = ("\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m")
_RESET = "\033[0m"

_ALIASES = {
    "TRACE": TRACE, "DEBUG": TRACE, "ALL": TRACE, "0": TRACE,
    "INFO": INFO, "1": INFO,
    "WARN": WARN, "WARNING": WARN, "2": WARN,
    "ERROR": ERROR, "ERR": ERROR, "3": ERROR,
    "FATAL": FATAL, "CRITICAL": FATAL, "4": FATAL,
    "OFF": OFF, "NONE": OFF, "SILENT": OFF, "5": OFF,
}

_TRUE = ("1", "true", "yes", "on")
_FALSE = ("0", "false", "no", "off")

_lock = threading.Lock()


def _parse_level(value, fallback):
    if not value:
        return fallback
    return _ALIASES.get(value.strip().upper(), fallback)


def _parse_bool(value):
    """1 on, 0 off, None unrecognised."""
    if not value:
        return None
    low = value.strip().lower()
    if low in _TRUE:
        return True
    if low in _FALSE:
        return False
    return None


def _isatty(stream):
    try:
        return bool(stream.isatty())
    except Exception:
        # A stream replaced by a test harness or a captured pipe may not
        # implement isatty() at all.
        return False


def _init():
    global _min_level, _use_color, _stream, _file

    _min_level = _parse_level(os.environ.get("LOG_LEVEL"), TRACE)

    stream = (os.environ.get("LOG_STREAM") or "").strip().lower()
    _stream = stream if stream in ("stdout", "stderr") else "split"

    forced = _parse_bool(os.environ.get("LOG_COLOR"))
    if forced is not None:
        _use_color = forced
    elif os.environ.get("NO_COLOR"):
        _use_color = False
    elif _stream == "stdout":
        _use_color = _isatty(sys.stdout)
    elif _stream == "stderr":
        _use_color = _isatty(sys.stderr)
    else:
        _use_color = _isatty(sys.stdout) and _isatty(sys.stderr)

    _file = None
    path = os.environ.get("LOG_FILE")
    if path:
        try:
            _file = open(path, "a", encoding="utf-8")
        except OSError:
            _file = None


_init()


def set_level(level):
    """Raise or lower the threshold. Accepts a constant or a name."""
    global _min_level
    if isinstance(level, str):
        level = _parse_level(level, _min_level)
    with _lock:
        _min_level = level


def get_level():
    return _min_level


def set_color(enabled):
    global _use_color
    with _lock:
        _use_color = bool(enabled)


def set_log_file(path):
    """Append log output to `path`, or pass None to go back to the terminal."""
    global _file
    new = open(path, "a", encoding="utf-8") if path else None
    with _lock:
        old, _file = _file, new
    if old is not None:
        try:
            old.close()
        except OSError:
            pass


def flush():
    with _lock:
        target = _file
    if target is not None:
        target.flush()
    else:
        sys.stdout.flush()
        sys.stderr.flush()


def _timestamp():
    now = time.time()
    local = time.localtime(now)
    return "%02d:%02d:%02d.%03d" % (
        local.tm_hour, local.tm_min, local.tm_sec, int((now % 1) * 1000),
    )


def _caller(depth):
    try:
        frame = sys._getframe(depth)
    except (ValueError, AttributeError):
        return "<unknown>", 0
    return os.path.basename(frame.f_code.co_filename), frame.f_lineno


def log(level, msg, *args, **kwargs):
    """Log at `level`. `depth` shifts which frame is reported as the caller,
    which is what you want when wrapping these functions in your own helper."""
    if level < _min_level or _min_level >= OFF:
        if level == FATAL:
            sys.exit(1)
        return

    depth = kwargs.pop("depth", 2)
    if kwargs:
        raise TypeError("unexpected keyword arguments: %s" % ", ".join(kwargs))

    if not isinstance(msg, str):
        msg = str(msg)
    if args:
        try:
            msg = msg % args
        except (TypeError, ValueError):
            # Better to log the pieces than to raise out of a log call.
            msg = "%s %r" % (msg, args)

    filename, line = _caller(depth)
    text = "[%s][%s] %s:%d -> %s" % (_timestamp(), _NAMES[level], filename, line, msg)

    with _lock:
        target = _file
        colored = _use_color
        stream = _stream

        if target is not None:
            target.write(text + "\n")
            target.flush()
        else:
            if stream == "stdout":
                out = sys.stdout
            elif stream == "stderr":
                out = sys.stderr
            else:
                out = sys.stderr if level >= ERROR else sys.stdout
            out.write(_COLORS[level] + text + _RESET + "\n" if colored else text + "\n")
            out.flush()

    if level == FATAL:
        sys.exit(1)


def trace(msg, *args, **kwargs):
    kwargs.setdefault("depth", 3)
    log(TRACE, msg, *args, **kwargs)


def info(msg, *args, **kwargs):
    kwargs.setdefault("depth", 3)
    log(INFO, msg, *args, **kwargs)


def warn(msg, *args, **kwargs):
    kwargs.setdefault("depth", 3)
    log(WARN, msg, *args, **kwargs)


def error(msg, *args, **kwargs):
    kwargs.setdefault("depth", 3)
    log(ERROR, msg, *args, **kwargs)


def fatal(msg, *args, **kwargs):
    """Log at FATAL, then exit with status 1."""
    kwargs.setdefault("depth", 3)
    log(FATAL, msg, *args, **kwargs)
