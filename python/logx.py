"""
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
"""

import inspect
import sys
import os
import threading
from datetime import datetime

_LEVELS = {
    'TRACE': 0,
    'INFO':  1,
    'WARN':  2,
    'ERROR': 3,
    'FATAL': 4,
}

_NAMES = ['TRACE', 'INFO ', 'WARN ', 'ERROR', 'FATAL']
_COLORS = {
    'TRACE': '\033[36m',
    'INFO':  '\033[32m',
    'WARN':  '\033[33m',
    'ERROR': '\033[31m',
    'FATAL': '\033[35m',
}

_MIN_LEVEL = _LEVELS.get(os.environ.get('LOG_LEVEL', '').upper(), 0)

_COLOR_ENV = os.environ.get('LOG_COLOR', '')
if _COLOR_ENV:
    _USE_COLOR = _COLOR_ENV in ('1', 'yes')
else:
    _USE_COLOR = sys.stderr.isatty() and sys.stdout.isatty()

_FILE = None
_LOCK = threading.Lock()


def set_log_file(path):
    global _FILE
    if path:
        _FILE = open(path, 'a')
    else:
        if _FILE:
            _FILE.close()
        _FILE = None


def _timestamp():
    now = datetime.now()
    return now.strftime('%H:%M:%S.') + f'{now.microsecond // 1000:03d}'


def _log(level, msg, file, line):
    if _LEVELS.get(level, 0) < _MIN_LEVEL:
        return

    ts = _timestamp()
    label = f'[{ts}][{level}] {file}:{line} -> {msg}'

    with _LOCK:
        if _FILE:
            _FILE.write(label + '\n')
            _FILE.flush()
        else:
            out = sys.stderr if level in ('ERROR', 'FATAL') else sys.stdout
            if _USE_COLOR:
                out.write(f'{_COLORS[level]}{label}\033[0m\n')
            else:
                out.write(label + '\n')
            out.flush()

    if level == 'FATAL':
        sys.exit(1)


def _caller(depth=2):
    frame = inspect.currentframe()
    for _ in range(depth):
        if frame:
            frame = frame.f_back
    if frame:
        info = inspect.getframeinfo(frame)
        return info.filename, info.lineno
    return '<unknown>', 0


def _make_logger(level):
    def logger(msg):
        f, l = _caller(2)
        _log(level, msg, os.path.basename(f), l)
    return logger


trace = _make_logger('TRACE')
info  = _make_logger('INFO')
warn  = _make_logger('WARN')
error = _make_logger('ERROR')
fatal = _make_logger('FATAL')


__all__ = ['trace', 'info', 'warn', 'error', 'fatal', 'set_log_file']
