/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

/*
 * logx -- single-file logger for Node, Bun and Deno.
 *
 *   const { info, warn, error } = require('./logx');
 *
 *   info('listening on port %d', 8080);
 *   warn('memory at %.1f%%', 74.2);
 *   error('connection lost');
 *
 * This file is CommonJS, which is what makes `require()` work and also lets
 * `import { info } from './logx.js'` work in a CommonJS package. If your
 * package.json says "type": "module", save this file as logx.cjs instead --
 * Node then reads it as CommonJS and named imports still work:
 *
 *   import { info } from './logx.cjs';
 *
 * Environment
 *   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
 *   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
 *   NO_COLOR    set to anything to disable color (https://no-color.org)
 *   LOG_FILE    path to append to instead of writing to the terminal
 *   LOG_STREAM  split (default) | stdout | stderr
 */

'use strict';

const TRACE = 0;
const INFO = 1;
const WARN = 2;
const ERROR = 3;
const FATAL = 4;
const OFF = 5;

const NAMES = ['TRACE', 'INFO ', 'WARN ', 'ERROR', 'FATAL'];
const COLORS = ['\x1b[36m', '\x1b[32m', '\x1b[33m', '\x1b[31m', '\x1b[35m'];
const RESET = '\x1b[0m';

const ALIASES = {
  TRACE: TRACE, DEBUG: TRACE, ALL: TRACE, 0: TRACE,
  INFO: INFO, 1: INFO,
  WARN: WARN, WARNING: WARN, 2: WARN,
  ERROR: ERROR, ERR: ERROR, 3: ERROR,
  FATAL: FATAL, CRITICAL: FATAL, 4: FATAL,
  OFF: OFF, NONE: OFF, SILENT: OFF, 5: OFF,
};

// Deno exposes process too, but guard anyway so a bundled copy of this file
// does not explode in a browser.
const env = (typeof process !== 'undefined' && process.env) ? process.env : {};

function parseLevel(value, fallback) {
  if (!value) return fallback;
  const key = String(value).trim().toUpperCase();
  return Object.prototype.hasOwnProperty.call(ALIASES, key) ? ALIASES[key] : fallback;
}

function parseBool(value) {
  if (!value) return null;
  const low = String(value).trim().toLowerCase();
  if (low === '1' || low === 'true' || low === 'yes' || low === 'on') return true;
  if (low === '0' || low === 'false' || low === 'no' || low === 'off') return false;
  return null;
}

let minLevel = parseLevel(env.LOG_LEVEL, TRACE);
let stream = (() => {
  const s = String(env.LOG_STREAM || '').trim().toLowerCase();
  return s === 'stdout' || s === 'stderr' ? s : 'split';
})();

let useColor = (() => {
  const forced = parseBool(env.LOG_COLOR);
  if (forced !== null) return forced;
  if (env.NO_COLOR) return false;
  if (typeof process === 'undefined') return false;
  if (stream === 'stdout') return Boolean(process.stdout && process.stdout.isTTY);
  if (stream === 'stderr') return Boolean(process.stderr && process.stderr.isTTY);
  return Boolean(process.stdout && process.stdout.isTTY &&
                 process.stderr && process.stderr.isTTY);
})();

let logFd = null;

function openLogFile(filePath) {
  // A plain fd with synchronous appends, not a WriteStream: a WriteStream
  // buffers, and process.exit() on FATAL would drop whatever is still queued.
  const fs = require('fs');
  return fs.openSync(filePath, 'a');
}

function closeLogFile() {
  if (logFd === null) return;
  try { require('fs').closeSync(logFd); } catch (_) { /* already gone */ }
  logFd = null;
}

/** Append log output to `filePath`, or pass null to go back to the terminal. */
function setLogFile(filePath) {
  closeLogFile();
  if (filePath) logFd = openLogFile(filePath);
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
  if (logFd !== null) {
    try { require('fs').fsyncSync(logFd); } catch (_) { /* not a real file */ }
  }
}

if (env.LOG_FILE) {
  try { setLogFile(env.LOG_FILE); } catch (_) { /* unwritable: stay on the terminal */ }
}

function timestamp() {
  const now = new Date();
  const pad = (n, w) => String(n).padStart(w, '0');
  return pad(now.getHours(), 2) + ':' + pad(now.getMinutes(), 2) + ':' +
         pad(now.getSeconds(), 2) + '.' + pad(now.getMilliseconds(), 3);
}

const FRAME = /(?:\()?(?:async\s+)?(?:file:\/\/)?([^()\s]+):(\d+):(\d+)\)?$/;

// Both the SELF probe and callerInfo() go through this, so frames written as
// `at f (/x/logx.js:1:1)` and `at file:///x/logx.js:1:1` reduce to the same
// path and compare equal.
function parseFrame(line) {
  const m = FRAME.exec(line.trim());
  return m ? [m[1], parseInt(m[2], 10)] : null;
}

// Every frame raised inside this file belongs to logx; the first frame that is
// not ours is the caller. Counting frames breaks the moment someone wraps these
// functions, so match on the path instead.
const SELF = (() => {
  const lines = (new Error().stack || '').split('\n');
  for (let i = 1; i < lines.length; i++) {
    const frame = parseFrame(lines[i]);
    if (frame) return frame[0];
  }
  return typeof __filename === 'string' ? __filename : '';
})();

function callerInfo() {
  const stack = new Error().stack;
  if (!stack) return ['<unknown>', 0];
  const lines = stack.split('\n');
  for (let i = 1; i < lines.length; i++) {
    const frame = parseFrame(lines[i]);
    if (!frame) continue;
    const file = frame[0];
    if (file === SELF || file.startsWith('node:')) continue;
    const slash = Math.max(file.lastIndexOf('/'), file.lastIndexOf('\\'));
    return [slash >= 0 ? file.slice(slash + 1) : file, frame[1]];
  }
  return ['<unknown>', 0];
}

// util.format gives %s %d %i %f %j %o %O and %% plus inspection of objects.
// Loaded lazily so this file stays usable where `util` is absent.
let formatImpl = null;
function format(args) {
  if (args.length === 0) return '';
  if (args.length === 1) {
    return typeof args[0] === 'string' ? args[0] : inspectOne(args[0]);
  }
  if (formatImpl === null) {
    try { formatImpl = require('util').format; } catch (_) { formatImpl = false; }
  }
  if (formatImpl) return formatImpl.apply(null, args);
  return args.map((a) => (typeof a === 'string' ? a : inspectOne(a))).join(' ');
}

function inspectOne(value) {
  if (typeof value === 'string') return value;
  if (value instanceof Error) return value.stack || String(value);
  try { return require('util').inspect(value, { depth: 4 }); } catch (_) { /* fall through */ }
  try { return JSON.stringify(value); } catch (_) { return String(value); }
}

function write(level, args) {
  if (level < minLevel || minLevel >= OFF) {
    if (level === FATAL && typeof process !== 'undefined') process.exit(1);
    return;
  }

  const [file, line] = callerInfo();
  const text = '[' + timestamp() + '][' + NAMES[level] + '] ' + file + ':' + line +
               ' -> ' + format(args);

  if (logFd !== null) {
    try {
      require('fs').writeSync(logFd, text + '\n');
    } catch (_) {
      // The file went away under us; do not lose the line.
      process.stderr.write(text + '\n');
    }
  } else if (typeof process !== 'undefined') {
    const out = stream === 'stdout' ? process.stdout
              : stream === 'stderr' ? process.stderr
              : (level >= ERROR ? process.stderr : process.stdout);
    out.write(useColor ? COLORS[level] + text + RESET + '\n' : text + '\n');
  } else {
    // Browser or other host: console is all we have.
    (level >= ERROR ? console.error : console.log)(text);
  }

  if (level === FATAL && typeof process !== 'undefined') process.exit(1);
}

function trace() { write(TRACE, Array.prototype.slice.call(arguments)); }
function info()  { write(INFO,  Array.prototype.slice.call(arguments)); }
function warn()  { write(WARN,  Array.prototype.slice.call(arguments)); }
function error() { write(ERROR, Array.prototype.slice.call(arguments)); }
function fatal() { write(FATAL, Array.prototype.slice.call(arguments)); }
function log(level) { write(level, Array.prototype.slice.call(arguments, 1)); }

// Assigned one by one (not as an object literal) so Node's CommonJS lexer can
// see the names and offer them to `import { info } from './logx.cjs'`.
exports.TRACE = TRACE;
exports.INFO = INFO;
exports.WARN = WARN;
exports.ERROR = ERROR;
exports.FATAL = FATAL;
exports.OFF = OFF;
exports.trace = trace;
exports.info = info;
exports.warn = warn;
exports.error = error;
exports.fatal = fatal;
exports.log = log;
exports.setLevel = setLevel;
exports.getLevel = getLevel;
exports.setLogFile = setLogFile;
exports.setColor = setColor;
exports.flush = flush;
