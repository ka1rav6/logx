<p align="center">
  <img src="https://img.shields.io/badge/languages-10-blue?style=flat-square" alt="10 languages">
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen?style=flat-square" alt="Zero deps">
  <img src="https://img.shields.io/badge/license-BSD%202--Clause-yellow?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/setup-copy/paste-red?style=flat-square" alt="Copy paste">
  <img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20Windows-lightgrey?style=flat-square" alt="Platform">
</p>

<h1 align="center">LogX</h1>

<p align="center">
  <strong>One file. Ten languages. Zero dependencies.</strong><br>
  <em>Copy. Paste. Log.</em>
</p>

---

## What if logging were this easy?

```python
from logx import info, warn, error

info("Server started on port %d", 8080)
warn("Memory at %.1f%%", 74.2)
error("Connection lost")
```

```c
LOGX_INFO("Server started on port %d", 8080);
LOGX_WARN("Memory at %.1f%%", 74.2);
LOGX_ERROR("Connection lost");
```

```rust
logx_info!("Server started on port {}", 8080);
logx_warn!("Memory at {:.1}%", 74.2);
logx_error!("Connection lost");
```

```js
const { info } = require('logx');
info("Server started on port %d", 8080);
```

No installs. No config files. No hunting down 200 transitive deps.

---

## Table of Contents

- [Why LogX?](#why-logx)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [API Reference](#api-reference)
- [Environment Variables](#environment-variables)
- [Output Format](#output-format)
- [Philosophy](#philosophy)
- [Contributing](#contributing)
- [Publishing to GitHub](#publishing-to-github)
- [License](#license)

---

## Why LogX?

Logging should be as easy as `print()`. But `print()` doesn't give you levels, timestamps, colors, or file output.

Most logging libraries give you all that — and also give you a headache. Setup, configuration, dependencies, framework lock-in...

LogX is the opposite. One file per language. Same API philosophy everywhere. Drop it in, include it, done.

### Why not just `print()`?

| Feature            | `print()` | LogX |
|--------------------|-----------|------|
| Log levels         | ❌        | ✅ TRACE, INFO, WARN, ERROR, FATAL |
| Timestamps         | ❌        | ✅ `[HH:MM:SS.mmm]` |
| File & line        | ❌        | ✅ Automatic |
| Colored output     | ❌        | ✅ Auto TTY detection |
| File logging       | ❌        | ✅ Optional, one call |
| Thread safe        | ❌        | ✅ Mutex-guarded |
| Level filtering    | ❌        | ✅ `LOG_LEVEL=WARN ./app` |
| Still one file     | ✅        | ✅ |

---

## Quick Start

| Language   | File             | Include                                            |
|------------|------------------|----------------------------------------------------|
| Python     | `python/logx/__init__.py` | `from logx import info`                          |
| JavaScript | `js/logx.js`     | `const { info } = require('./logx')`               |
| TypeScript | `ts/logx.ts`     | `import { info } from './logx'`                     |
| C          | `c/logx.h`       | `#include "logx.h"` → `LOGX_INFO(...)`              |
| C++        | `cpp/logx.h`     | `#include "logx.h"` → `LOGX_INFO << ...`            |
| Rust       | `rust/logx.rs`   | `#[macro_use] mod logx;` → `logx_info!(...)`        |
| Go         | `go/logx.go`     | `import "yourmodule/logx"` → `logx.Info(...)`       |
| Java       | `java/logx.java` | `import Logx;` → `Logx.info(...)`                   |
| Zig        | `zig/logx.zig`   | `@import("logx.zig")` → `logx.log(.info, ...)`      |
| Assembly   | `asm/logx.asm`   | `%include "logx.asm"` → `log_info "..."`            |

---

## Installation

### Copy-paste (any language)

1. Copy the relevant file from this repo into your project.
2. Include/import it.
3. Start logging.

### pip (Python)

```bash
pip install python-logx
```

```python
from logx import trace, info, warn, error, fatal, set_log_file

info("hello %d", 42)
error("something broke")

set_log_file("/tmp/app.log")  # redirect to file
```

### npm (JavaScript / TypeScript)

```bash
npm install logx
```

```javascript
const { trace, info, warn, error, fatal, setLogFile } = require('logx');

info('hello %d', 42);
error('something broke');
```

```typescript
import { trace, info, warn, error, fatal, setLogFile } from 'logx';

info('hello %d', 42);
error('something broke');
```

### C

```c
#include "logx.h"

int main() {
    LOGX_INFO("hello %d", 42);
    LOGX_ERROR("something broke");
}
```

```c
// Optional: log to file
lx_set_log_file("/tmp/app.log");
```

```bash
gcc -std=c11 main.c -o app -lpthread
```

### C++

```cpp
#include "logx.h"

int main() {
    LOGX_INFO << "hello " << 42;
    LOGX_ERROR << "something broke";
}
```

```cpp
// Optional: log to file
Logx::setLogFile("/tmp/app.log");
Logx::setLogFile();  // back to terminal
```

```bash
g++ -std=c++11 main.cpp -o app
```

### Rust

```rust
#[macro_use] mod logx;

fn main() {
    logx_info!("hello {}", 42);
    logx_error!("something broke");
}
```

```rust
// Optional: log to file
logx::set_log_file("/tmp/app.log");
```

Add to `Cargo.toml`:
```toml
[dependencies]
libc = "0.2"
```

### Go

```go
package main

import "yourmodule/logx"

func main() {
    logx.Info("hello %d", 42)
    logx.Error("something broke")
}
```

```go
// Optional: log to file
logx.SetLogFile("/tmp/app.log")
```

### Java

```java
public class Main {
    public static void main(String[] args) {
        Logx.info("hello %d", 42);
        Logx.error("something broke");
    }
}
```

```java
// Optional: log to file
Logx.setLogFile("/tmp/app.log");
```

```bash
javac Logx.java Main.java && java Main
```

### Zig

```zig
const logx = @import("logx.zig");

pub fn main() void {
    logx.log(.info, "hello 42", @src());
    logx.log(.error, "something broke", @src());
}
```

```zig
// Optional: log to file
try logx.setLogFile("/tmp/app.log");
```

### x86-64 Assembly (Linux, NASM)

```asm
%include "logx.asm"

section .data
log_str(msg_hello, "hello 42")
log_str(msg_error, "something broke")

section .text
global _start
_start:
    call log_init
    log_info msg_hello
    log_error msg_error
    call log_close

    mov rax, 60
    xor rdi, rdi
    syscall
```

```asm
; Optional: log to file (define before including)
%define LOG_FILE_PATH "/tmp/app.log"
%include "logx.asm"
```

```bash
nasm -felf64 main.asm -o main.o && ld main.o -o main
```

---

## API Reference

### Log Levels

| Level | Value | Description |
|-------|-------|-------------|
| TRACE | 0     | Finest-grained diagnostic |
| INFO  | 1     | General operational info |
| WARN  | 2     | Something unexpected (non-fatal) |
| ERROR | 3     | Runtime error or failure |
| FATAL | 4     | Unrecoverable — exits the process |

### Per-language API

| Language   | Log calls                                    | Set log file                              | Clear log file |
|------------|----------------------------------------------|-------------------------------------------|----------------|
| Python     | `trace()`, `info()`, `warn()`, `error()`, `fatal()` | `set_log_file(path)`              | `set_log_file(None)` |
| JavaScript | `trace()`, `info()`, `warn()`, `error()`, `fatal()` | `setLogFile(path)`                | `setLogFile(null)` |
| TypeScript | `trace()`, `info()`, `warn()`, `error()`, `fatal()` | `setLogFile(path)`                | `setLogFile(null)` |
| C          | `LOGX_TRACE()`, `LOGX_INFO()`, `LOGX_WARN()`, `LOGX_ERROR()`, `LOGX_FATAL()` | `lx_set_log_file(path)` | `lx_set_log_file(NULL)` |
| C++        | `LOGX_TRACE <<`, `LOGX_INFO <<`, `LOGX_WARN <<`, `LOGX_ERROR <<`, `LOGX_FATAL <<` | `Logx::setLogFile(path)` | `Logx::setLogFile()` |
| Rust       | `logx_trace!()`, `logx_info!()`, `logx_warn!()`, `logx_error!()`, `logx_fatal!()` | `set_log_file(path)` | — |
| Go         | `logx.Trace()`, `logx.Info()`, `logx.Warn()`, `logx.Error()`, `logx.Fatal()` | `logx.SetLogFile(path)` | `logx.SetLogFile("")` |
| Java       | `Logx.trace()`, `Logx.info()`, `Logx.warn()`, `Logx.error()`, `Logx.fatal()` | `Logx.setLogFile(path)` | `Logx.setLogFile(null)` |
| Zig        | `logx.log(.trace,)`, `logx.log(.info,)`, `logx.log(.warn,)`, `logx.log(.err,)`, `logx.log(.fatal,)` | `logx.setLogFile(path)` | — |
| Assembly   | `log_trace`, `log_info`, `log_warn`, `log_error`, `log_fatal` | `%define LOG_FILE_PATH` before include | `call log_close` |

---

## Environment Variables

| Variable    | Values                     | Default                                                        |
|-------------|----------------------------|----------------------------------------------------------------|
| `LOG_LEVEL` | `TRACE`, `INFO`, `WARN`, `ERROR`, `FATAL` | `TRACE`                                          |
| `LOG_COLOR` | `0`, `1`, `yes`            | Auto (enabled if both stdout and stderr are TTYs)              |

Example:

```bash
LOG_LEVEL=WARN LOG_COLOR=0 ./myapp
```

## Output Format

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

Example:

```
[14:23:01.042][INFO ] server.c:42 -> Server started on port 8080
[14:23:01.043][WARN ] memory.c:17 -> Memory at 74.2%
[14:23:01.044][ERROR] network.c:89 -> Connection lost
```

---

## Philosophy

LogX is not trying to replace OpenTelemetry. It is built for:

- Prototypes & hackathons
- CLI tools & scripts
- Game jams
- Students learning a new language
- Small-to-medium projects
- Anyone who just wants to log without ceremony

> *"If you can write print(), you already know how to use LogX."*

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Publishing to GitHub

### 1. Create the repository on GitHub

```bash
# Install GitHub CLI if you haven't
# https://cli.github.com/

# Authenticate
gh auth login

# Create the repo (from inside the project directory)
gh repo create logx --public --source=. --remote=origin --push
```

Or manually:

```bash
# Create a repo on github.com, then:
git remote add origin https://github.com/YOUR_USERNAME/logx.git
git branch -M main
git push -u origin main
```

### 2. Publish to package registries

**npm (JavaScript / TypeScript):**

```bash
# Make sure you're logged in
npm login

# Publish from js/ directory
cd js
npm publish

# Publish from ts/ directory
cd ../ts
npm publish
```

**PyPI (Python):**

```bash
cd python
pip install build twine
python -m build
python -m twine upload dist/*
```

**crates.io (Rust):**

```bash
cd rust
cargo login
cargo publish
```

### 3. Create a release

```bash
git tag v1.0.0
git push origin v1.0.0

# Or via GitHub CLI:
gh release create v1.0.0 --title "v1.0.0" --notes "Initial release"
```

### 4. Recommended GitHub repo settings

- **Description**: *"One file. Ten languages. Zero dependencies. — A copy-paste logging library for Python, JS, TS, C, C++, Rust, Go, Java, Zig, and Assembly."*
- **Topics**: `logging`, `logger`, `zero-dependency`, `single-file`, `python`, `javascript`, `typescript`, `c`, `cpp`, `rust`, `go`, `java`, `zig`, `assembly`
- **Website**: (optional) Link to your GitHub Pages or personal site

---

## Project Structure

```
logger/
├── asm/logx.asm          # x86-64 Assembly (Linux, NASM)
├── c/logx.h              # C99/C11
├── cpp/logx.h            # C++11
├── go/logx.go            # Go
├── java/logx.java        # Java
├── js/logx.js            # JavaScript (Node)
├── python/logx/          # Python
│   └── __init__.py
├── rust/logx.rs          # Rust
├── ts/logx.ts            # TypeScript
├── zig/logx.zig          # Zig
├── test/                 # Tests per language
├── README.md
├── CONTRIBUTING.md
├── LICENSE               # BSD 2-Clause
└── .gitignore
```

---

## License

BSD 2-Clause. See [LICENSE](LICENSE).
