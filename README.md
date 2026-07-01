# Logger

Single-file loggers in 9 languages — same API philosophy everywhere.

- **Single file** — drop it in your project, `#include` / `import` / `require`, and start logging
- **5 levels** — `TRACE`, `INFO`, `WARN`, `ERROR`, `FATAL` (FATAL exits)
- **Timestamps** — `[HH:MM:SS.mmm]` on every line
- **File & line** — automatically captured
- **Colors** — auto-detected by terminal; override with `LOG_COLOR=0` / `LOG_COLOR=1`
- **Level filtering** — `LOG_LEVEL=WARN ./app` silences everything below WARN
- **File logging** — optional; call `setLogFile("/path/to/log")` or similar
- **Thread safe** — mutex-guarded output where applicable

---

## C++  (`cpp/Logger.h`)

```cpp
#include "Logger.h"

int main() {
    LOG_INFO << "hello " << 42;
    LOG_ERROR << "something broke";
}
```

```
g++ -std=c++11 main.cpp -o app
```

```cpp
// Optional: log to file
Logger::setLogFile("/tmp/app.log");   // redirect all output to file
Logger::setLogFile();                 // close file, go back to terminal
```

---

## C  (`c/logger.h`)

```c
#include "logger.h"

int main() {
    LOG_INFO("hello %d", 42);
    LOG_ERROR("something broke");
}
```

```c
// Optional: log to file
cl_set_log_file("/tmp/app.log");
```

```
gcc -std=c11 main.c -o app -lpthread
```

---

## Python  (`python/logger.py`)

```python
from logger import trace, info, warn, error, fatal, set_log_file

info("hello %d", 42)
error("something broke")

# Optional: log to file
set_log_file("/tmp/app.log")
```

```
python3 main.py
```

---

## Java  (`java/Logger.java` — single class, no deps)

```java
public class Main {
    public static void main(String[] args) {
        Logger.info("hello %d", 42);
        Logger.error("something broke");
    }
}
```

```java
// Optional: log to file
Logger.setLogFile("/tmp/app.log");
```

```
javac Logger.java Main.java && java Main
```

---

## JavaScript (Node)  (`js/logger.js`)

```javascript
const { trace, info, warn, error, fatal, setLogFile } = require('./logger');

info('hello %d', 42);
error('something broke');

// Optional: log to file
setLogFile('/tmp/app.log');
```

```
node main.js
```

---

## TypeScript  (`ts/logger.ts`)

```typescript
import { trace, info, warn, error, fatal, setLogFile } from './logger';

info('hello %d', 42);
error('something broke');

// Optional: log to file
setLogFile('/tmp/app.log');
```

```
npx tsx main.ts
```

---

## Rust  (`rust/logger.rs`)

```rust
#[macro_use] mod logger;

fn main() {
    log_info!("hello {}", 42);
    log_error!("something broke");
}
```

```rust
// Optional: log to file
logger::set_log_file("/tmp/app.log");
```

Requires `libc` crate for terminal detection. Add to `Cargo.toml`:
```toml
[dependencies]
libc = "0.2"
```

---

## Go  (`go/logger.go`)

```go
package main

import "yourmodule/logger"

func main() {
    logger.Info("hello %d", 42)
    logger.Error("something broke")
}
```

```go
// Optional: log to file
logger.SetLogFile("/tmp/app.log")
```

```
go run main.go
```

---

## Zig  (`zig/logger.zig`)

```zig
const logger = @import("logger.zig");

pub fn main() void {
    logger.log(.info, "hello 42", @src());
    logger.log(.error, "something broke", @src());
}
```

```zig
// Optional: log to file
try logger.setLogFile("/tmp/app.log");
```

```
zig build-exe main.zig logger.zig
```

---

## x86-64 Assembly (Linux, NASM)  (`asm/logger.asm`)

```asm
%include "logger.asm"

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
%include "logger.asm"
```

```
nasm -felf64 main.asm -o main.o && ld main.o -o main
```

---

## Environment variables

| Variable     | Values                          | Default                                 |
|--------------|---------------------------------|-----------------------------------------|
| `LOG_LEVEL`  | `TRACE`, `INFO`, `WARN`, `ERROR`, `FATAL` | `TRACE`                       |
| `LOG_COLOR`  | `0`, `1`, `yes`                 | auto (enabled if both stdout/stderr are TTYs) |

## Output format

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

## License

BSD 2-Clause.  See `LICENSE`.
