/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

import * as fs from 'node:fs';
import * as path from 'node:path';

const LEVELS = { TRACE: 0, INFO: 1, WARN: 2, ERROR: 3, FATAL: 4 } as const;
type LevelName = keyof typeof LEVELS;

const NAMES: Record<LevelName, string> = { TRACE: 'TRACE', INFO: 'INFO ', WARN: 'WARN ', ERROR: 'ERROR', FATAL: 'FATAL' };
const COLORS: Record<LevelName, string> = {
  TRACE: '\x1b[36m', INFO: '\x1b[32m', WARN: '\x1b[33m',
  ERROR: '\x1b[31m', FATAL: '\x1b[35m',
};
const RESET = '\x1b[0m';

const envLevel = (process.env.LOG_LEVEL ?? '').toUpperCase();
const minLevel = LEVELS[envLevel as LevelName] ?? 0;

const colEnv = process.env.LOG_COLOR ?? '';
const useColor = colEnv ? colEnv === '1' || colEnv === 'yes' : process.stdout.isTTY && process.stderr.isTTY;

let logFile: fs.WriteStream | null = null;

export function setLogFile(filePath: string | null): void {
  if (logFile) logFile.close();
  logFile = filePath ? fs.createWriteStream(filePath, { flags: 'a' }) : null;
}

function timestamp(): string {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  const ms = String(now.getMilliseconds()).padStart(3, '0');
  return `${hh}:${mm}:${ss}.${ms}`;
}

function callerInfo(depth: number): [string, number] {
  const err = new Error();
  if (!err.stack) return ['<unknown>', 0];
  const lines = err.stack.split('\n');
  // depth: 0=this fn, 1=log, 2=trace/info/etc, 3=user
  const target = 3 + depth;
  if (target >= lines.length) return ['<unknown>', 0];
  const m = lines[target].match(/(?:\/|)([^/]+?):(\d+):\d+\)?$/);
  return m ? [m[1], parseInt(m[2])] : ['<unknown>', 0];
}

function write(level: LevelName, msg: string, skip: number): void {
  if (LEVELS[level] < minLevel) return;
  const [file, line] = callerInfo(skip);
  const ts = timestamp();
  const label = `[${ts}][${NAMES[level]}] ${file}:${line} -> ${msg}`;

  if (logFile) {
    logFile.write(label + '\n');
  } else {
    const out = LEVELS[level] >= LEVELS.ERROR ? process.stderr : process.stdout;
    if (useColor) {
      out.write(COLORS[level] + label + RESET + '\n');
    } else {
      out.write(label + '\n');
    }
  }

  if (level === 'FATAL') process.exit(1);
}

export const trace = (msg: string) => write('TRACE', msg, 0);
export const info  = (msg: string) => write('INFO',  msg, 0);
export const warn  = (msg: string) => write('WARN',  msg, 0);
export const error = (msg: string) => write('ERROR', msg, 0);
export const fatal = (msg: string) => write('FATAL', msg, 0);
