const assert = require('assert');
const path = require('path');
const fs = require('fs');
const os = require('os');

process.env.LOG_LEVEL = 'TRACE';
process.env.LOG_COLOR = '0';

delete require.cache[require.resolve('../../js/logx')];
const logx = require('../../js/logx');

const captured = { stdout: [], stderr: [] };
const origStdoutWrite = process.stdout.write.bind(process.stdout);
const origStderrWrite = process.stderr.write.bind(process.stderr);

function captureStart() {
  captured.stdout = [];
  captured.stderr = [];
  process.stdout.write = (chunk) => { captured.stdout.push(chunk.toString()); return true; };
  process.stderr.write = (chunk) => { captured.stderr.push(chunk.toString()); return true; };
}

function captureEnd() {
  process.stdout.write = origStdoutWrite;
  process.stderr.write = origStderrWrite;
  return { stdout: captured.stdout.join(''), stderr: captured.stderr.join('') };
}

async function testBasicOutput() {
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
  const tmpFile = path.join(os.tmpdir(), `logx_js_test_${Date.now()}.log`);
  logx.setLogFile(tmpFile);
  logx.info('file test');
  logx.setLogFile(null);

  // Wait for the async createWriteStream to flush
  await new Promise(r => setTimeout(r, 50));

  const content = fs.readFileSync(tmpFile, 'utf8');
  fs.unlinkSync(tmpFile);

  assert.ok(content.includes('file test'), 'file log message');
  assert.ok(content.includes('INFO '), 'file log level');
  console.log('PASS: testFileLogging');
}

async function testLevelFiltering() {
  delete require.cache[require.resolve('../../js/logx')];
  process.env.LOG_LEVEL = 'ERROR';
  const logx2 = require('../../js/logx');

  captureStart();
  logx2.trace('should not appear');
  logx2.info('should not appear');
  logx2.error('should appear');
  const { stdout, stderr } = captureEnd();

  assert.strictEqual(stdout, '', 'no stdout with LOG_LEVEL=ERROR');
  assert.ok(stderr.includes('should appear'), 'ERROR message in stderr');
  console.log('PASS: testLevelFiltering');
}

(async () => {
  await testBasicOutput();
  await testFileLogging();
  await testLevelFiltering();
  console.log('\nAll JS tests passed');
})();
