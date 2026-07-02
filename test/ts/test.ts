import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { strict as assert } from 'node:assert';

process.env.LOG_LEVEL = 'TRACE';
process.env.LOG_COLOR = '0';

const logx = await import('../../ts/logx.js');

const captured: { stdout: string[]; stderr: string[] } = { stdout: [], stderr: [] };
const origStdoutWrite = process.stdout.write.bind(process.stdout);
const origStderrWrite = process.stderr.write.bind(process.stderr);

function captureStart() {
  captured.stdout = [];
  captured.stderr = [];
  process.stdout.write = (chunk: any) => { captured.stdout.push(String(chunk)); return true; };
  process.stderr.write = (chunk: any) => { captured.stderr.push(String(chunk)); return true; };
}

function captureEnd(): { stdout: string; stderr: string } {
  process.stdout.write = origStdoutWrite;
  process.stderr.write = origStderrWrite;
  return { stdout: captured.stdout.join(''), stderr: captured.stderr.join('') };
}

function testBasicOutput() {
  captureStart();
  logx.trace('trace msg');
  logx.info('info msg');
  logx.warn('warn msg');
  logx.error('error msg');
  const { stdout, stderr } = captureEnd();

  assert.ok(stdout.includes('TRACE'), 'TRACE in stdout');
  assert.ok(stdout.includes('trace msg'), 'trace msg in stdout');
  assert.ok(stdout.includes('INFO '), 'INFO in stdout');
  assert.ok(stdout.includes('info msg'), 'info msg in stdout');
  assert.ok(stdout.includes('WARN '), 'WARN in stdout');
  assert.ok(stdout.includes('warn msg'), 'warn msg in stdout');
  assert.ok(stderr.includes('ERROR'), 'ERROR in stderr');
  assert.ok(stderr.includes('error msg'), 'error msg in stderr');
  console.log('PASS: testBasicOutput');
}

async function testFileLogging() {
  const tmpFile = path.join(os.tmpdir(), `logx_ts_test_${Date.now()}.log`);
  logx.setLogFile(tmpFile);
  logx.info('file test');
  logx.setLogFile(null);

  await new Promise(r => setTimeout(r, 50));

  const content = fs.readFileSync(tmpFile, 'utf8');
  fs.unlinkSync(tmpFile);

  assert.ok(content.includes('file test'), 'file log message');
  assert.ok(content.includes('INFO '), 'file log level');
  console.log('PASS: testFileLogging');
}

testBasicOutput();
await testFileLogging();

console.log('\nAll TS tests passed');
