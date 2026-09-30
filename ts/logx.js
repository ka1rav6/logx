"use strict";
/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/
Object.defineProperty(exports, "__esModule", { value: true });
exports.OFF = exports.FATAL = exports.ERROR = exports.WARN = exports.INFO = exports.TRACE = void 0;
exports.setLogFile = setLogFile;
exports.setLevel = setLevel;
exports.getLevel = getLevel;
exports.setColor = setColor;
exports.flush = flush;
exports.log = log;
exports.trace = trace;
exports.info = info;
exports.warn = warn;
exports.error = error;
exports.fatal = fatal;
/*
 * logx -- single-file logger for TypeScript.
 *
 *   import { info, warn, error } from './logx';
 *
 *   info('listening on port %d', 8080);
 *   warn('memory at %s%%', 74.2);
 *   error('connection lost');
 *
 * No top-level `node:` imports, so this file compiles and runs unchanged under
 * CommonJS, ESM, Deno, Bun and browser bundlers. `node:fs` is resolved at call
 * time and only when file logging is actually requested.
 *
 * Environment
 *   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
 *   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
 *   NO_COLOR    set to anything to disable color (https://no-color.org)
 *   LOG_FILE    path to append to instead of writing to the terminal
 *   LOG_STREAM  split (default) | stdout | stderr
 */
exports.TRACE = 0;
exports.INFO = 1;
exports.WARN = 2;
exports.ERROR = 3;
exports.FATAL = 4;
exports.OFF = 5;
const NAMES = ['TRACE', 'INFO ', 'WARN ', 'ERROR', 'FATAL'];
const COLORS = ['\x1b[36m', '\x1b[32m', '\x1b[33m', '\x1b[31m', '\x1b[35m'];
const RESET = '\x1b[0m';
const ALIASES = {
    TRACE: exports.TRACE, DEBUG: exports.TRACE, ALL: exports.TRACE, '0': exports.TRACE,
    INFO: exports.INFO, '1': exports.INFO,
    WARN: exports.WARN, WARNING: exports.WARN, '2': exports.WARN,
    ERROR: exports.ERROR, ERR: exports.ERROR, '3': exports.ERROR,
    FATAL: exports.FATAL, CRITICAL: exports.FATAL, '4': exports.FATAL,
    OFF: exports.OFF, NONE: exports.OFF, SILENT: exports.OFF, '5': exports.OFF,
};
const proc = globalThis.process;
const env = proc?.env ?? {};
function parseLevel(value, fallback) {
    if (!value)
        return fallback;
    const key = String(value).trim().toUpperCase();
    return Object.prototype.hasOwnProperty.call(ALIASES, key) ? ALIASES[key] : fallback;
}
function parseBool(value) {
    if (!value)
        return null;
    const low = String(value).trim().toLowerCase();
    if (low === '1' || low === 'true' || low === 'yes' || low === 'on')
        return true;
    if (low === '0' || low === 'false' || low === 'no' || low === 'off')
        return false;
    return null;
}
let minLevel = parseLevel(env.LOG_LEVEL, exports.TRACE);
const sink = (() => {
    const s = String(env.LOG_STREAM ?? '').trim().toLowerCase();
    return s === 'stdout' || s === 'stderr' ? s : 'split';
})();
let useColor = (() => {
    const forced = parseBool(env.LOG_COLOR);
    if (forced !== null)
        return forced;
    if (env.NO_COLOR)
        return false;
    if (sink === 'stdout')
        return Boolean(proc?.stdout?.isTTY);
    if (sink === 'stderr')
        return Boolean(proc?.stderr?.isTTY);
    return Boolean(proc?.stdout?.isTTY && proc?.stderr?.isTTY);
})();
/* Resolved on demand: `require` under CommonJS, process.getBuiltinModule under
 * ESM. Left null when neither is available (a browser bundle), in which case
 * setLogFile() reports it rather than failing silently. */
let fsCache;
function getFs() {
    if (fsCache !== undefined)
        return fsCache;
    fsCache = null;
    try {
        const req = globalThis.require;
        if (typeof req === 'function') {
            fsCache = req('fs');
        }
        else if (typeof proc?.getBuiltinModule === 'function') {
            fsCache = proc.getBuiltinModule('node:fs');
        }
    }
    catch {
        fsCache = null;
    }
    return fsCache;
}
let logFd = null;
/** Append log output to `path`, or pass null to go back to the terminal. */
function setLogFile(path) {
    const fs = getFs();
    if (logFd !== null && fs) {
        try {
            fs.closeSync(logFd);
        }
        catch { /* already gone */ }
    }
    logFd = null;
    if (!path)
        return;
    if (!fs)
        throw new Error('logx: file logging needs a filesystem; none is available here');
    logFd = fs.openSync(path, 'a');
}
/** Raise or lower the threshold. Accepts a constant or a name. */
function setLevel(level) {
    minLevel = typeof level === 'string' ? parseLevel(level, minLevel) : level;
}
function getLevel() {
    return minLevel;
}
function setColor(enabled) {
    useColor = Boolean(enabled);
}
function flush() {
    /* Writes are synchronous, so there is nothing buffered to push. */
}
if (env.LOG_FILE) {
    try {
        setLogFile(env.LOG_FILE);
    }
    catch { /* unwritable: stay on the terminal */ }
}
function pad(value, width) {
    return String(value).padStart(width, '0');
}
function timestamp() {
    const now = new Date();
    return pad(now.getHours(), 2) + ':' + pad(now.getMinutes(), 2) + ':' +
        pad(now.getSeconds(), 2) + '.' + pad(now.getMilliseconds(), 3);
}
const FRAME = /(?:\()?(?:async\s+)?(?:file:\/\/)?([^()\s]+):(\d+):(\d+)\)?$/;
/* Both the SELF probe and callerInfo() go through this, so an ESM frame
 * (`at file:///x/logx.js:1:1`) and a CommonJS one (`at f (/x/logx.js:1:1)`)
 * reduce to the same path and compare equal. */
function parseFrame(line) {
    const m = FRAME.exec(line.trim());
    return m ? [m[1], parseInt(m[2], 10)] : null;
}
/* Frames raised inside this file belong to logx; the first frame that is not
 * ours is the caller. Counting frames breaks as soon as someone wraps these
 * functions, so match on the path instead. */
const SELF = (() => {
    const lines = (new Error().stack ?? '').split('\n');
    for (let i = 1; i < lines.length; i++) {
        const frame = parseFrame(lines[i]);
        if (frame)
            return frame[0];
    }
    return '';
})();
function callerInfo() {
    const stack = new Error().stack;
    if (!stack)
        return ['<unknown>', 0];
    const lines = stack.split('\n');
    for (let i = 1; i < lines.length; i++) {
        const frame = parseFrame(lines[i]);
        if (!frame)
            continue;
        const [file, line] = frame;
        if (file === SELF || file.startsWith('node:'))
            continue;
        const slash = Math.max(file.lastIndexOf('/'), file.lastIndexOf('\\'));
        return [slash >= 0 ? file.slice(slash + 1) : file, line];
    }
    return ['<unknown>', 0];
}
function stringify(value) {
    if (typeof value === 'string')
        return value;
    if (value instanceof Error)
        return value.stack ?? String(value);
    if (value === null)
        return 'null';
    if (value === undefined)
        return 'undefined';
    if (typeof value === 'object') {
        try {
            return JSON.stringify(value) ?? String(value);
        }
        catch {
            return String(value);
        }
    }
    return String(value);
}
/* printf-style placeholders, matching what util.format accepts:
 * %s %d %i %f %j %o %O and %% for a literal percent. Extra arguments are
 * appended, which is what console.log does too. */
function format(args) {
    if (args.length === 0)
        return '';
    const first = args[0];
    if (typeof first !== 'string')
        return args.map(stringify).join(' ');
    if (args.length === 1)
        return first;
    let next = 1;
    const out = first.replace(/%[sdifjoO%]/g, (token) => {
        if (token === '%%')
            return '%';
        if (next >= args.length)
            return token;
        const value = args[next++];
        switch (token[1]) {
            case 's': return typeof value === 'string' ? value : stringify(value);
            case 'd':
            case 'f': return typeof value === 'bigint' ? String(value) : String(Number(value));
            case 'i': {
                if (typeof value === 'bigint')
                    return String(value);
                const n = Number(value);
                return Number.isNaN(n) ? 'NaN' : String(Math.trunc(n));
            }
            case 'j':
                try {
                    return JSON.stringify(value) ?? 'undefined';
                }
                catch {
                    return '[Circular]';
                }
            default: return stringify(value);
        }
    });
    const rest = args.slice(next).map(stringify);
    return rest.length ? out + ' ' + rest.join(' ') : out;
}
function log(level, ...args) {
    if (level < minLevel || minLevel >= exports.OFF) {
        if (level === exports.FATAL)
            proc?.exit?.(1);
        return;
    }
    const [file, line] = callerInfo();
    const text = '[' + timestamp() + '][' + NAMES[level] + '] ' + file + ':' + line +
        ' -> ' + format(args);
    const fs = logFd !== null ? getFs() : null;
    if (fs && logFd !== null) {
        fs.writeSync(logFd, text + '\n');
    }
    else if (proc?.stdout && proc?.stderr) {
        const out = sink === 'stdout' ? proc.stdout
            : sink === 'stderr' ? proc.stderr
                : (level >= exports.ERROR ? proc.stderr : proc.stdout);
        out.write(useColor ? COLORS[level] + text + RESET + '\n' : text + '\n');
    }
    else {
        (level >= exports.ERROR ? console.error : console.log)(text);
    }
    if (level === exports.FATAL)
        proc?.exit?.(1);
}
function trace(...args) { log(exports.TRACE, ...args); }
function info(...args) { log(exports.INFO, ...args); }
function warn(...args) { log(exports.WARN, ...args); }
function error(...args) { log(exports.ERROR, ...args); }
/** Log at FATAL, then exit with status 1. */
function fatal(...args) { log(exports.FATAL, ...args); }
