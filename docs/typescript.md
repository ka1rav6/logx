# LogX for TypeScript

Single-file logger written in TypeScript. No imports at all — not even
`node:fs` — so it compiles and runs unchanged under CommonJS, ESM, Deno, Bun
and browser bundlers.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Formatting](#formatting)
- [Why it has no imports](#why-it-has-no-imports)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| TypeScript | Any version with `strict` support. Compiles under `--strict`. |
| Types | **None.** It does not need `@types/node`. |
| Runtime | Node, Deno, Bun, or a browser bundle |
| Module format | CommonJS or ESM, both from the same source |

## Install

```bash
npm install logx
```

Or copy `ts/logx.ts` into your project and import it directly — then it is
compiled by your own build with your own settings, which is usually what you
want for a single file.

```typescript
import { info } from './logx';
```

The npm package also ships a compiled `logx.js` plus `logx.d.ts`, so a plain
JavaScript project can consume it too.

## Quick start

```typescript
import { trace, info, warn, error } from './logx';

trace('starting up');
info('listening on port %d', 8080);
warn('memory at %s%%', 74.2);
error('connection lost: %s', reason);
```

```
[14:23:01.042][TRACE] server.ts:3 -> starting up
[14:23:01.042][INFO ] server.ts:4 -> listening on port 8080
[14:23:01.043][WARN ] server.ts:5 -> memory at 74.2%
[14:23:01.043][ERROR] server.ts:6 -> connection lost: ECONNRESET
```

## API reference

### Types

```typescript
type Level = 0 | 1 | 2 | 3 | 4 | 5;

type LevelName =
  | 'TRACE' | 'DEBUG' | 'ALL'
  | 'INFO'
  | 'WARN' | 'WARNING'
  | 'ERROR' | 'ERR'
  | 'FATAL' | 'CRITICAL'
  | 'OFF' | 'NONE' | 'SILENT';
```

`Level` is a union of literal types rather than an enum, so the constants stay
plain numbers and no runtime enum object is emitted.

### Log functions

```typescript
function trace(...args: unknown[]): void;
function info (...args: unknown[]): void;
function warn (...args: unknown[]): void;
function error(...args: unknown[]): void;
function fatal(...args: unknown[]): void;   // logs, then process.exit(1)

function log(level: Level, ...args: unknown[]): void;
```

Arguments are `unknown[]`, not `any[]` — you can pass anything, and nothing
leaks `any` into your code.

### Configuration

```typescript
function setLevel(level: Level | LevelName): void;
function getLevel(): Level;
function setColor(enabled: boolean): void;
function setLogFile(path: string | null): void;
function flush(): void;
```

`setLevel` accepts either form, and `LevelName` gives you autocomplete on the
string:

```typescript
setLevel('WARN');          // checked at compile time
setLevel(logx.WARN);       // also fine
setLevel('WRAN');          // compile error: not assignable to Level | LevelName
```

### Constants

```typescript
const TRACE = 0, INFO = 1, WARN = 2, ERROR = 3, FATAL = 4, OFF = 5;
```

## Formatting

The same placeholders `util.format` accepts, implemented without importing it:

| Token | Meaning |
|---|---|
| `%s` | string |
| `%d`, `%f` | number |
| `%i` | integer (truncated) |
| `%j` | JSON, `[Circular]` if it cannot serialise |
| `%o`, `%O` | stringified value |
| `%%` | a literal `%` |

```typescript
info('port %d', 8080);              // port 8080
info('as json %j', { a: 1 });       // as json {"a":1}
info('truncated %i', 42.9);         // truncated 42
info('extra args', 1, 2);           // extra args 1 2
info('100% done');                  // 100% done  (no args: untouched)
```

Unmatched arguments are appended, as `console.log` does. An `Error` logs its
`.stack`.

## Why it has no imports

A top-level `import * as fs from 'node:fs'` would be a hard dependency on a
Node-shaped runtime. Every browser bundler would then have to be told to shim or
exclude it, and the file would not load in a plain browser build at all.

Instead `logx.ts` declares the minimal shapes it needs:

```typescript
interface WritableLike { write(chunk: string): unknown; isTTY?: boolean }
interface ProcessLike { env?: ...; stdout?: ...; exit?(code?: number): never; ... }
interface FsLike { openSync(...): number; writeSync(...): number; closeSync(...): void }
```

and resolves the real thing at call time, only when you ask for file logging:
`require` under CommonJS, `process.getBuiltinModule('node:fs')` under ESM. On a
runtime with no filesystem, `setLogFile` throws a clear message and console
logging carries on.

The practical consequences:

- No `@types/node` needed to compile.
- Works in a browser bundle, where it falls back to `console`.
- `setLogFile` needs a CommonJS build, or Node 22.3+ for ESM. Everything else
  works everywhere.

## Recipes

### A typed wrapper

```typescript
import * as logx from './logx';

interface Request { method: string; url: string }
interface Response { statusCode: number }

export function logRequest(req: Request, res: Response): void {
  const level: logx.Level = res.statusCode >= 500 ? logx.ERROR : logx.INFO;
  logx.log(level, '%s %s -> %d', req.method, req.url, res.statusCode);
}
```

Note the reported line is the one **inside** `logRequest`, not the caller's —
see [Gotchas](#gotchas).

### Narrowing a level from configuration

```typescript
import { setLevel, type LevelName } from './logx';

function applyConfig(cfg: { logLevel?: string }): void {
  // LevelName is a plain union, so a runtime check narrows it cleanly.
  const names: readonly LevelName[] = ['TRACE', 'INFO', 'WARN', 'ERROR', 'FATAL', 'OFF'];
  const found = names.find((n) => n === cfg.logLevel?.toUpperCase());
  if (found) setLevel(found);
}
```

An unrecognised `LOG_LEVEL` is already ignored in favour of the default, so this
is only needed when the level comes from your own config file.

### Deno

```typescript
import { info, setLevel } from './logx.ts';

setLevel('INFO');
info('running under Deno %s', Deno.version.deno);
```

Needs `--allow-env` to read `LOG_LEVEL` and friends, and `--allow-write` if you
call `setLogFile`.

### Browser

Bundle it like any other module. With no `process`, it falls back to
`console.log` / `console.error`, keeps the record format, and skips color and
file output.

```typescript
import { info } from './logx';
info('cart has %d items', items.length);
// console.log: [14:23:01.042][INFO ] cart.ts:2 -> cart has 3 items
```

Bundled without source maps, the reported file and line are the bundle's.

### tsconfig that compiles it

Nothing special is required. These are the only settings that matter:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "strict": true
  }
}
```

`ES2020` is for `String.prototype.padStart` and optional chaining. Any
`module` setting works.

## Gotchas

**A wrapper reports its own line, not its caller's.** Frame skipping removes
`logx`'s own frames and stops at the first one outside — which is your wrapper.
TypeScript has no depth parameter and no caller-location builtin. Python has
`depth=` and Go has `skip`; TypeScript, JavaScript and Java do not.

**`fatal()` calls `process.exit(1)`** where a `process` exists, and is a plain
log elsewhere. No `finally` blocks run after it.

**`setLogFile` needs a filesystem.** Under ESM it wants Node 22.3+ for
`process.getBuiltinModule`; under CommonJS it always works. In a browser it
throws `logx: file logging needs a filesystem; none is available here`.

**`flush()` is a no-op.** Writes are synchronous, so there is nothing buffered.
It exists for API parity with the other languages.

**Levels are read when the module loads.** Mutating `process.env.LOG_LEVEL`
after the import does nothing; use `setLevel()`.

**Arguments are not lazy.** `info('x %s', expensive())` always calls
`expensive()`.

## Troubleshooting

**`Cannot find name 'process'`** — you are compiling with `@types/node`
absent *and* referencing `process` in your own code. `logx.ts` itself does not
need it; the error is from your file, not this one.

**`Top-level await is currently not supported with the "cjs" output format`** —
you used `await import('./logx.js')` in a file being compiled to CommonJS. Use a
static `import`, or name the file `.mts`.

**Every line reports `logx.js` or a bundle path** — the stack is reporting
compiled output. Enable source maps, or accept the compiled location.

**`logx: file logging needs a filesystem`** — `setLogFile` on a runtime with no
reachable `fs`. See [Why it has no imports](#why-it-has-no-imports).

**No color in a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be TTYs. Force it with `LOG_COLOR=1` or
`setColor(true)`.

**Importing from `'logx'` gives no types** — check that `logx.d.ts` is next to
`logx.js` in `node_modules/logx`. When copying the file in by hand, import
`./logx` (the `.ts`), not a compiled `.js`.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [LogX for JavaScript](javascript.md) — the CommonJS sibling
- [`ts/logx.ts`](../ts/logx.ts) — the source
- [`test/ts/test.mts`](../test/ts/test.mts) — worked examples
