/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

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

export const TRACE = 0;
export const INFO = 1;
export const WARN = 2;
export const ERROR = 3;
export const FATAL = 4;
export const OFF = 5;

export type Level = 0 | 1 | 2 | 3 | 4 | 5;
export type LevelName =
  | 'TRACE' | 'DEBUG' | 'ALL'
  | 'INFO'
  | 'WARN' | 'WARNING'
  | 'ERROR' | 'ERR'
  | 'FATAL' | 'CRITICAL'
  | 'OFF' | 'NONE' | 'SILENT';

const NAMES = ['TRACE', 'INFO ', 'WARN ', 'ERROR', 'FATAL'];
const COLORS = ['\x1b[36m', '\x1b[32m', '\x1b[33m', '\x1b[31m', '\x1b[35m'];
const RESET = '\x1b[0m';

const ALIASES: Record<string, Level> = {
  TRACE: TRACE, DEBUG: TRACE, ALL: TRACE, '0': TRACE,
  INFO: INFO, '1': INFO,
  WARN: WARN, WARNING: WARN, '2': WARN,
  ERROR: ERROR, ERR: ERROR, '3': ERROR,
  FATAL: FATAL, CRITICAL: FATAL, '4': FATAL,
  OFF: OFF, NONE: OFF, SILENT: OFF, '5': OFF,
};

/* Minimal shapes so this file needs no @types/node to compile. */
interface WritableLike { write(chunk: string): unknown; isTTY?: boolean }
interface ProcessLike {
  env?: Record<string, string | undefined>;
  stdout?: WritableLike;
  stderr?: WritableLike;
  exit?(code?: number): never;
  getBuiltinModule?(id: string): unknown;
}
interface FsLike {
  openSync(path: string, flags: string): number;
  writeSync(fd: number, data: string): number;
  closeSync(fd: number): void;
}

const proc: ProcessLike | undefined = (globalThis as { process?: ProcessLike }).process;
const env: Record<string, string | undefined> = proc?.env ?? {};

function parseLevel(value: string | undefined, fallback: Level): Level {
  if (!value) return fallback;
  const key = String(value).trim().toUpperCase();
  return Object.prototype.hasOwnProperty.call(ALIASES, key) ? ALIASES[key] : fallback;
}

function parseBool(value: string | undefined): boolean | null {
  if (!value) return null;
  const low = String(value).trim().toLowerCase();
  if (low === '1' || low === 'true' || low === 'yes' || low === 'on') return true;
  if (low === '0' || low === 'false' || low === 'no' || low === 'off') return false;
  return null;
}

let minLevel: Level = parseLevel(env.LOG_LEVEL, TRACE);

const sink: 'split' | 'stdout' | 'stderr' = (() => {
  const s = String(env.LOG_STREAM ?? '').trim().toLowerCase();
  return s === 'stdout' || s === 'stderr' ? s : 'split';
})();

let useColor: boolean = (() => {
  const forced = parseBool(env.LOG_COLOR);
  if (forced !== null) return forced;
  if (env.NO_COLOR) return false;
  if (sink === 'stdout') return Boolean(proc?.stdout?.isTTY);
  if (sink === 'stderr') return Boolean(proc?.stderr?.isTTY);
  return Boolean(proc?.stdout?.isTTY && proc?.stderr?.isTTY);
})();

/* Resolved on demand: `require` under CommonJS, process.getBuiltinModule under
 * ESM. Left null when neither is available (a browser bundle), in which case
 * setLogFile() reports it rather than failing silently. */
let fsCache: FsLike | null | undefined;
function getFs(): FsLike | null {
  if (fsCache !== undefined) return fsCache;
  fsCache = null;
  try {
    const req = (globalThis as { require?: (id: string) => unknown }).require;
    if (typeof req === 'function') {
      fsCache = req('fs') as FsLike;
    } else if (typeof proc?.getBuiltinModule === 'function') {
      fsCache = proc.getBuiltinModule('node:fs') as FsLike;
    }
  } catch {
    fsCache = null;
  }
  return fsCache;
}

let logFd: number | null = null;

/** Append log output to `path`, or pass null to go back to the terminal. */
export function setLogFile(path: string | null): void {
  const fs = getFs();
  if (logFd !== null && fs) {
    try { fs.closeSync(logFd); } catch { /* already gone */ }
  }
  logFd = null;
  if (!path) return;
  if (!fs) throw new Error('logx: file logging needs a filesystem; none is available here');
  logFd = fs.openSync(path, 'a');
}

/** Raise or lower the threshold. Accepts a constant or a name. */
export function setLevel(level: Level | LevelName): void {
  minLevel = typeof level === 'string' ? parseLevel(level, minLevel) : level;
}

export function getLevel(): Level {
  return minLevel;
}

export function setColor(enabled: boolean): void {
  useColor = Boolean(enabled);
}

export function flush(): void {
  /* Writes are synchronous, so there is nothing buffered to push. */
}

if (env.LOG_FILE) {
  try { setLogFile(env.LOG_FILE); } catch { /* unwritable: stay on the terminal */ }
}

function pad(value: number, width: number): string {
  return String(value).padStart(width, '0');
}

function timestamp(): string {
  const now = new Date();
  return pad(now.getHours(), 2) + ':' + pad(now.getMinutes(), 2) + ':' +
         pad(now.getSeconds(), 2) + '.' + pad(now.getMilliseconds(), 3);
}

const FRAME = /(?:\()?(?:async\s+)?(?:file:\/\/)?([^()\s]+):(\d+):(\d+)\)?$/;

/* Both the SELF probe and callerInfo() go through this, so an ESM frame
 * (`at file:///x/logx.js:1:1`) and a CommonJS one (`at f (/x/logx.js:1:1)`)
 * reduce to the same path and compare equal. */
function parseFrame(line: string): [string, number] | null {
  const m = FRAME.exec(line.trim());
  return m ? [m[1], parseInt(m[2], 10)] : null;
}

/* Frames raised inside this file belong to logx; the first frame that is not
 * ours is the caller. Counting frames breaks as soon as someone wraps these
 * functions, so match on the path instead. */
const SELF: string = (() => {
  const lines = (new Error().stack ?? '').split('\n');
  for (let i = 1; i < lines.length; i++) {
    const frame = parseFrame(lines[i]);
    if (frame) return frame[0];
  }
  return '';
})();

function callerInfo(): [string, number] {
  const stack = new Error().stack;
  if (!stack) return ['<unknown>', 0];
  const lines = stack.split('\n');
  for (let i = 1; i < lines.length; i++) {
    const frame = parseFrame(lines[i]);
    if (!frame) continue;
    const [file, line] = frame;
    if (file === SELF || file.startsWith('node:')) continue;
    const slash = Math.max(file.lastIndexOf('/'), file.lastIndexOf('\\'));
    return [slash >= 0 ? file.slice(slash + 1) : file, line];
  }
  return ['<unknown>', 0];
}

function stringify(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value instanceof Error) return value.stack ?? String(value);
  if (value === null) return 'null';
  if (value === undefined) return 'undefined';
  if (typeof value === 'object') {
    try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
  }
  return String(value);
}

/* printf-style placeholders, matching what util.format accepts:
 * %s %d %i %f %j %o %O and %% for a literal percent. Extra arguments are
 * appended, which is what console.log does too. */
function format(args: unknown[]): string {
  if (args.length === 0) return '';
  const first = args[0];
  if (typeof first !== 'string') return args.map(stringify).join(' ');
  if (args.length === 1) return first;

  let next = 1;
  const out = first.replace(/%[sdifjoO%]/g, (token) => {
    if (token === '%%') return '%';
    if (next >= args.length) return token;
    const value = args[next++];
    switch (token[1]) {
      case 's': return typeof value === 'string' ? value : stringify(value);
      case 'd':
      case 'f': return typeof value === 'bigint' ? String(value) : String(Number(value));
      case 'i': {
        if (typeof value === 'bigint') return String(value);
        const n = Number(value);
        return Number.isNaN(n) ? 'NaN' : String(Math.trunc(n));
      }
      case 'j':
        try { return JSON.stringify(value) ?? 'undefined'; } catch { return '[Circular]'; }
      default: return stringify(value);
    }
  });

  const rest = args.slice(next).map(stringify);
  return rest.length ? out + ' ' + rest.join(' ') : out;
}

export function log(level: Level, ...args: unknown[]): void {
  if (level < minLevel || minLevel >= OFF) {
    if (level === FATAL) proc?.exit?.(1);
    return;
  }

  const [file, line] = callerInfo();
  const text = '[' + timestamp() + '][' + NAMES[level] + '] ' + file + ':' + line +
               ' -> ' + format(args);

  const fs = logFd !== null ? getFs() : null;
  if (fs && logFd !== null) {
    fs.writeSync(logFd, text + '\n');
  } else if (proc?.stdout && proc?.stderr) {
    const out = sink === 'stdout' ? proc.stdout
              : sink === 'stderr' ? proc.stderr
              : (level >= ERROR ? proc.stderr : proc.stdout);
    out.write(useColor ? COLORS[level] + text + RESET + '\n' : text + '\n');
  } else {
    (level >= ERROR ? console.error : console.log)(text);
  }

  if (level === FATAL) proc?.exit?.(1);
}

export function trace(...args: unknown[]): void { log(TRACE, ...args); }
export function info(...args: unknown[]): void { log(INFO, ...args); }
export function warn(...args: unknown[]): void { log(WARN, ...args); }
export function error(...args: unknown[]): void { log(ERROR, ...args); }

/** Log at FATAL, then exit with status 1. */
export function fatal(...args: unknown[]): void { log(FATAL, ...args); }
