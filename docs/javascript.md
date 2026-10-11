# LogX for JavaScript

Single-file logger for Node, Bun and Deno. No dependencies.

- [Requirements](#requirements)
- [Install](#install)
- [CommonJS and ESM](#commonjs-and-esm)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Formatting](#formatting)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Runtime | Node 18+, Bun, or Deno. Degrades to `console` elsewhere. |
| Dependencies | None |

## Install

```bash
npm install logx
```

Or copy `js/logx.js` into your project. Same file either way.

Writing TypeScript? Use [`ts/logx.ts`](typescript.md) instead — it is a proper
TypeScript source with types, not this file plus a `.d.ts`.

## CommonJS and ESM

`js/logx.js` is **CommonJS**. That is what makes `require()` work, and it also
lets named `import` work in a CommonJS package, because Node detects the
`exports.name = ...` assignments:

```javascript
const { info } = require('./logx');          // CommonJS package
import { info } from './logx.js';            // also fine in a CommonJS package
```

**If your `package.json` says `"type": "module"`, rename the file to
`logx.cjs`:**

```javascript
import { info, warn, setLevel } from './logx.cjs';
```

Node then reads it as CommonJS regardless of the package type, and named
imports still work.

No single `.js` file can be valid CommonJS *and* ESM — `export` is a syntax
error in one and `module.exports` is undefined in the other — so the extension
is the only lever. It is still one file; only the name changes.

Installing from npm sidesteps this entirely: the package declares
`"type": "commonjs"`, so `import { info } from 'logx'` works in an ESM project
without any renaming.

## Quick start

```javascript
const { trace, info, warn, error } = require('./logx');

trace('starting up');
info('listening on port %d', 8080);
warn('memory at %s%%', 74.2);
error('connection lost: %s', reason);
info('config:', { port: 8080, tls: true });
```

```
[14:23:01.042][TRACE] server.js:3 -> starting up
[14:23:01.042][INFO ] server.js:4 -> listening on port 8080
[14:23:01.043][WARN ] server.js:5 -> memory at 74.2%
[14:23:01.043][ERROR] server.js:6 -> connection lost: ECONNRESET
[14:23:01.043][INFO ] server.js:7 -> config: { port: 8080, tls: true }
```

Nothing to configure. The module reads the environment when it loads.

## API reference

### Log functions

```javascript
trace(...args)
info (...args)
warn (...args)
error(...args)
fatal(...args)          // logs, then process.exit(1)

log(level, ...args)     // a level chosen at runtime
```

### Configuration

```javascript
setLevel(level)         // a constant or a name: setLevel('WARN') or setLevel(logx.WARN)
getLevel()              // -> number
setColor(enabled)       // override the TTY detection
setLogFile(path)        // append to a file; null goes back to the terminal
flush()
```

### Levels

```javascript
logx.TRACE   // 0
logx.INFO    // 1
logx.WARN    // 2
logx.ERROR   // 3
logx.FATAL   // 4
logx.OFF     // 5  -- a threshold only; silences everything
```

```javascript
logx.setLevel('WARN');          // names are case-insensitive, 0-5 also work
logx.setLevel(logx.OFF);        // silent
```

### File output

```javascript
logx.setLogFile('/tmp/app.log');
logx.setLogFile(null);          // back to the terminal
```

Writes go through a plain file descriptor with `fs.writeSync`, not a
`WriteStream`. A stream buffers, and `process.exit(1)` on `fatal()` would drop
whatever was still queued — so the last line before a fatal, the one you
actually want, would be the one you lose.

`setLogFile` throws if the path cannot be opened:

```javascript
try {
  logx.setLogFile(path);
} catch (err) {
  logx.warn('could not open %s: %s', path, err.message);
}
```

## Formatting

Arguments go through `util.format`, the same formatter `console.log` uses:

| Token | Meaning |
|---|---|
| `%s` | string |
| `%d`, `%i` | number / integer |
| `%f` | float |
| `%j` | JSON |
| `%o`, `%O` | inspected object |
| `%%` | a literal `%` |

```javascript
info('port %d', 8080);                  // port 8080
info('memory at %s%%', 74.2);           // memory at 74.2%
info('as json %j', { a: 1 });           // as json {"a":1}
```

A message with **no** arguments is passed through untouched, so a literal `%`
needs no escaping:

```javascript
info('100% done');                      // 100% done
```

Extra arguments beyond the placeholders are appended, exactly as
`console.log` does:

```javascript
info('config:', { port: 8080 });        // config: { port: 8080 }
```

Objects are inspected to depth 4. An `Error` logs its `.stack`:

```javascript
error(new Error('boom'));
// -> Error: boom
//        at ... (full stack)
```

## Recipes

### Wrapping it in your own helper

Caller detection skips every frame belonging to `logx` and reports the first one
that does not — which is **your wrapper's own line**, not the line that called
your wrapper:

```javascript
// log.js
function logRequest(req, res) {
  logx.info('%s %s -> %d', req.method, req.url, res.statusCode);   // line 3
}
```

```
[14:23:01.044][INFO ] log.js:3 -> GET /health -> 200
```

That is usually what you want from a dedicated logging helper: `log.js:3`
identifies which helper produced the line. But if you need the *call site*,
JavaScript has no way to express it — there is no depth or skip parameter, and
no caller-location builtin. Python has `depth=`, Go has `skip`, and C uses
`__FILE__`/`__LINE__` from a macro; JavaScript, TypeScript and Java do not have
an equivalent.

Two ways to live with it:

```javascript
// Pass the interesting location as part of the message.
function logRequest(req, res, where) {
  logx.info('%s %s -> %d (from %s)', req.method, req.url, res.statusCode, where);
}

// Or do not wrap: make the helper return the pieces and log at the call site.
logx.info(...describeRequest(req, res));
```

What frame skipping *does* buy you is robustness: you never see `logx.js` and
its internals, and it keeps working through `async` frames and across bundlers.

### Express middleware

```javascript
const logx = require('./logx');

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const level = res.statusCode >= 500 ? logx.ERROR : logx.INFO;
    logx.log(level, '%s %s -> %d (%dms)',
             req.method, req.originalUrl, res.statusCode, Date.now() - start);
  });
  next();
});
```

### A per-module prefix

```javascript
function tagged(tag) {
  return (...args) => {
    const [first, ...rest] = args;
    logx.info(`[${tag}] ${first}`, ...rest);
  };
}

const log = tagged('db');
log('connected in %dms', 12);
// -> [db] connected in 12ms
```

As above, the reported line is the one inside `tagged`, not the `log(...)` call.

### Logging uncaught failures

```javascript
process.on('uncaughtException', (err) => {
  logx.fatal('uncaught exception: %s', err.stack);  // logs, then exits 1
});

process.on('unhandledRejection', (reason) => {
  logx.error('unhandled rejection: %s', reason);
});
```

### Quieting it inside tests

```javascript
beforeEach(() => logx.setLevel(logx.OFF));
afterEach(() => logx.setLevel(logx.TRACE));
```

Or set `LOG_LEVEL=OFF` in your test script.

### Capturing output in a test

`logx` writes to `process.stdout` and `process.stderr` on every call, so
stubbing `write` works:

```javascript
function capture(fn) {
  let out = '';
  const real = process.stdout.write.bind(process.stdout);
  process.stdout.write = (chunk) => { out += chunk; return true; };
  try { fn(); } finally { process.stdout.write = real; }
  return out;
}

assert(capture(() => logx.info('hi')).includes('hi'));
```

Or point it at a temp file with `setLogFile`, which is what the test suite does.

## Gotchas

**`fatal()` calls `process.exit(1)`.** No `finally` blocks after it, no
`beforeExit` handlers. It exits even when the level filter hid the message.

**`"type": "module"` needs the file renamed to `logx.cjs`.** See
[CommonJS and ESM](#commonjs-and-esm).

**Arguments are not lazy.** `info('x %s', expensive())` always calls
`expensive()`. Guard with `logx.getLevel() <= logx.TRACE` if it matters.

**Levels are read when the module loads.** Mutating `process.env.LOG_LEVEL`
after the `require` does nothing; use `setLevel()`.

**`setLogFile` throws on a bad path**, while a bad `LOG_FILE` environment
variable is swallowed so a misconfigured deploy cannot stop your program from
starting.

**Caller detection relies on `Error.prototype.stack`.** Under a bundler or
minifier without source maps you will see the bundle's file and line, not your
source. That is a property of the stack, not of LogX.

## Troubleshooting

**`SyntaxError: Unexpected token 'export'`, or `module is not defined`** —
the file is being read as ESM. Rename it to `logx.cjs`, or install from npm.

**`does not provide an export named 'info'`** — same cause. Node parsed
`logx.js` as ESM because the package is `"type": "module"`. Rename to
`logx.cjs`.

**Every line reports `logx.js` and the same line number** — you are on a
version from before this was fixed. Current versions skip logger frames; check
that `js/logx.js` contains a `parseFrame` function.

**Lines say `<unknown>:0`** — the runtime gave no usable stack. Rare; happens
in some sandboxed or heavily instrumented environments.

**No color in a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be TTYs. Piping either turns it off. Force it with
`LOG_COLOR=1` or `logx.setColor(true)`.

**Nothing logs** — check `logx.getLevel()`. `LOG_LEVEL=OFF` silences
everything.

**Lines lost on exit** — should not happen; writes are synchronous. If you see
it, confirm you are not holding an old `WriteStream`-based copy of the file.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [LogX for TypeScript](typescript.md)
- [`js/logx.js`](../js/logx.js) — the source
- [`test/js/test.js`](../test/js/test.js) — worked examples
