// Tests for ts/logx.ts. Run from the project root:
//   npx tsx test/ts/test.mts

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

process.env.LOG_LEVEL = 'TRACE';
process.env.LOG_COLOR = '0';
delete process.env.LOG_FILE;
delete process.env.LOG_STREAM;

const logx = await import('../../ts/logx.js');

const failures: string[] = [];

// [HH:MM:SS.mmm][LEVEL] file:line -> message
const RECORD = /^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\[(\w+ ?)\] ([^/\\:]+):(\d+) -> ([\s\S]*)$/;

function check(cond: boolean, what: string): void {
  if (cond) {
    console.log('PASS: ' + what);
  } else {
    console.log('FAIL: ' + what);
    failures.push(what);
  }
}

// Runs fn with output going to a temp file, returns the lines written.
function capture(fn: () => void): string[] {
  const file = path.join(os.tmpdir(), 'logx_ts_test_' + process.pid + '.log');
  logx.setLogFile(file);
  try {
    fn();
  } finally {
    logx.setLogFile(null);
  }
  const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
  fs.unlinkSync(file);
  return lines;
}

function testFormatAndArgs(): void {
  const lines = capture(() => {
    logx.trace('trace msg');
    logx.info('port %d', 8080);
    logx.warn('memory at %s%%', 74.2);
    logx.error('lost: %s', 'ECONNRESET');
    logx.info('literal 100% done');
    logx.info('json %j', { a: 1 });
    logx.info('truncated %i', 42.9);
    logx.info('extra args', 1, 2);
  });

  check(lines.length === 8, 'wrote one line per call');
  if (lines.length < 8) return;

  const parsed = lines.map((line) => RECORD.exec(line));
  check(parsed.every((m) => m !== null), 'every line matches the documented format');
  if (!parsed.every((m) => m !== null)) return;

  check(parsed[0]![1] === 'TRACE', 'TRACE label');
  check(parsed[1]![1] === 'INFO ', 'INFO label is padded to 5');
  check(parsed[2]![1] === 'WARN ', 'WARN label is padded to 5');
  check(parsed[3]![1] === 'ERROR', 'ERROR label');

  check(parsed[1]![4] === 'port 8080', 'format arguments are applied');
  check(parsed[2]![4] === 'memory at 74.2%', '%% and numbers survive');
  check(parsed[3]![4] === 'lost: ECONNRESET', '%s argument');
  check(parsed[4]![4] === 'literal 100% done', 'a lone % with no arguments is left alone');
  check(parsed[5]![4] === 'json {"a":1}', '%j serialises');
  check(parsed[6]![4] === 'truncated 42', '%i truncates to an integer');
  check(parsed[7]![4] === 'extra args 1 2', 'unmatched arguments are appended');

  check(parsed[0]![2] === 'test.mts', 'reports the calling file, not logx.ts');
}

function testCallerThroughAWrapper(): void {
  function myHelper(message: string): void {
    logx.info(message);
  }
  const lines = capture(() => myHelper('wrapped'));
  const match = RECORD.exec(lines[0]);
  check(match !== null && match[2] === 'test.mts',
        'a wrapper still reports the original file');
}

function testLevelFilter(): void {
  const lines = capture(() => {
    logx.setLevel('WARN');
    logx.trace('hidden');
    logx.info('hidden');
    logx.warn('shown');
    logx.error('shown');
    logx.setLevel(logx.OFF);
    logx.error('silenced by OFF');
    logx.setLevel(logx.TRACE);
  });
  check(lines.length === 2, 'only WARN and above passed the filter');
  check(logx.getLevel() === logx.TRACE, 'getLevel reflects setLevel');
}

function testStreams(): void {
  const seen = { out: '', err: '' };
  const realOut = process.stdout.write.bind(process.stdout);
  const realErr = process.stderr.write.bind(process.stderr);
  process.stdout.write = ((chunk: string) => { seen.out += chunk; return true; }) as never;
  process.stderr.write = ((chunk: string) => { seen.err += chunk; return true; }) as never;
  try {
    logx.info('to stdout');
    logx.error('to stderr');
  } finally {
    process.stdout.write = realOut as never;
    process.stderr.write = realErr as never;
  }
  check(seen.out.includes('to stdout'), 'INFO goes to stdout');
  check(!seen.err.includes('to stdout'), 'INFO stays off stderr');
  check(seen.err.includes('to stderr'), 'ERROR goes to stderr');
  check(!seen.out.includes('to stderr'), 'ERROR stays off stdout');
}

function testNoColorInFiles(): void {
  const lines = capture(() => {
    logx.setColor(true);
    logx.info('colored on the terminal only');
    logx.setColor(false);
  });
  check(!lines[0].includes('\x1b['), 'no color escapes in a file even with color on');
}

testFormatAndArgs();
testCallerThroughAWrapper();
testLevelFilter();
testStreams();
testNoColorInFiles();

console.log(failures.length ? 'TS tests FAILED' : 'all TS tests passed');
process.exit(failures.length ? 1 : 0);
