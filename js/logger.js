/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

const LEVELS = { TRACE: 0, INFO: 1, WARN: 2, ERROR: 3, FATAL: 4 };
const NAMES = { TRACE: 'TRACE', INFO: 'INFO ', WARN: 'WARN ', ERROR: 'ERROR', FATAL: 'FATAL' };
const COLORS = {
  TRACE: '\x1b[36m', INFO: '\x1b[32m', WARN: '\x1b[33m',
  ERROR: '\x1b[31m', FATAL: '\x1b[35m',
};
const RESET = '\x1b[0m';
const EOL = '\n';

let minLevel = (() => {
  const env = (process.env.LOG_LEVEL || '').toUpperCase();
  return LEVELS[env] ?? 0;
})();

let useColor = (() => {
  const env = process.env.LOG_COLOR || '';
  if (env) return env === '1' || env === 'yes';
  return process.stdout.isTTY && process.stderr.isTTY;
})();

let logFile = null;

function setLogFile(filePath) {
  if (logFile) { try { logFile.close(); } catch {} }
  if (filePath) {
    const fs = require('fs');
    logFile = fs.createWriteStream(filePath, { flags: 'a' });
  } else {
    logFile = null;
  }
}

function timestamp() {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  const ms = String(now.getMilliseconds()).padStart(3, '0');
  return `${hh}:${mm}:${ss}.${ms}`;
}

function callerInfo(skip) {
  const err = new Error();
  if (!err.stack) return ['<unknown>', 0];
  const lines = err.stack.split('\n');
  const idx = 3 + skip;
  if (idx >= lines.length) return ['<unknown>', 0];
  const m = lines[idx].match(/(?:\/|)([^/]+?):(\d+):\d+\)?$/);
  return m ? [m[1], parseInt(m[2])] : ['<unknown>', 0];
}

function write(level, msg, skip) {
  if (LEVELS[level] < minLevel) return;
  const [file, line] = callerInfo(skip);
  const ts = timestamp();
  const label = `[${ts}][${NAMES[level]}] ${file}:${line} -> ${msg}`;

  if (logFile) {
    logFile.write(label + EOL);
  } else {
    const out = LEVELS[level] >= LEVELS.ERROR ? process.stderr : process.stdout;
    if (useColor) {
      out.write(COLORS[level] + label + RESET + EOL);
    } else {
      out.write(label + EOL);
    }
  }

  if (level === 'FATAL') process.exit(1);
}

const trace = (msg) => write('TRACE', msg, 0);
const info  = (msg) => write('INFO',  msg, 0);
const warn  = (msg) => write('WARN',  msg, 0);
const error = (msg) => write('ERROR', msg, 0);
const fatal = (msg) => write('FATAL', msg, 0);

module.exports = { trace, info, warn, error, fatal, setLogFile };
