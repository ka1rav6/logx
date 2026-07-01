# Buggedd

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

## Menu

| Language   | File                                      |
|------------|-------------------------------------------|
| [C++](#cpp)     | `cpp/Buggedd.h`                  |
| [C](#c)         | `c/buggedd.h`                    |
| [Python](#py)   | `python/buggedd.py`     |
| [Java](#java)     | `java/Buggedd.java`          |
| [JavaScript (Node)](#js) | `js/buggedd.js` |
| [TypeScript](#ts) | `ts/buggedd.ts`       |
| [Rust](#rust)      | `rust/buggedd.rs`            |
| [Go](#go)         | `go/buggedd.go`                |
| [Zig](#zig)       | `zig/buggedd.zig`            |
| [x86-64 Assembly](#asm) | `asm/buggedd.asm` |

---

<a name="cpp"></a>
## C++  (`cpp/Buggedd.h`)

```cpp
#include "Buggedd.h"

int main() {
    BUGGED_INFO << "hello " << 42;
    BUGGED_ERROR << "something broke";
}
```

```
g++ -std=c++11 main.cpp -o app
```

```cpp
// Optional: log to file
Buggedd::setLogFile("/tmp/app.log");   // redirect all output to file
Buggedd::setLogFile();                 // close file, go back to terminal
```

---

<a name="c"></a>
## C  (`c/buggedd.h`)

```c
#include "buggedd.h"

int main() {
    BUGGED_INFO("hello %d", 42);
    BUGGED_ERROR("something broke");
}
```

```c
// Optional: log to file
bd_set_log_file("/tmp/app.log");
```

```
gcc -std=c11 main.c -o app -lpthread
```

---

<a name="py"></a>
## Python  (`python/buggedd.py`)

```python
from buggedd import trace, info, warn, error, fatal, set_log_file

info("hello %d", 42)
error("something broke")

# Optional: log to file
set_log_file("/tmp/app.log")
```

```
python3 main.py
```

---

<a name="java"></a>
## Java  (`java/Buggedd.java` — single class, no deps)

```java
public class Main {
    public static void main(String[] args) {
        Buggedd.info("hello %d", 42);
        Buggedd.error("something broke");
    }
}
```

```java
// Optional: log to file
Buggedd.setLogFile("/tmp/app.log");
```

```
javac Buggedd.java Main.java && java Main
```

---

<a name="js"></a>
## JavaScript (Node)  (`js/buggedd.js`)

```javascript
const { trace, info, warn, error, fatal, setLogFile } = require('./buggedd');

info('hello %d', 42);
error('something broke');

// Optional: log to file
setLogFile('/tmp/app.log');
```

```
node main.js
```

---

<a name="ts"></a>
## TypeScript  (`ts/buggedd.ts`)

```typescript
import { trace, info, warn, error, fatal, setLogFile } from './buggedd';

info('hello %d', 42);
error('something broke');

// Optional: log to file
setLogFile('/tmp/app.log');
```

```
npx tsx main.ts
```

---

<a name="rust"></a>
## Rust  (`rust/buggedd.rs`)

```rust
#[macro_use] mod buggedd;

fn main() {
    log_info!("hello {}", 42);
    log_error!("something broke");
}
```

```rust
// Optional: log to file
buggedd::set_log_file("/tmp/app.log");
```

Requires `libc` crate for terminal detection. Add to `Cargo.toml`:
```toml
[dependencies]
libc = "0.2"
```

---

<a name="go"></a>
## Go  (`go/buggedd.go`)

```go
package main

import "yourmodule/buggedd"

func main() {
    buggedd.Info("hello %d", 42)
    buggedd.Error("something broke")
}
```

```go
// Optional: log to file
buggedd.SetLogFile("/tmp/app.log")
```

```
go run main.go
```

---

<a name="zig"></a>
## Zig  (`zig/buggedd.zig`)

```zig
const buggedd = @import("buggedd.zig");

pub fn main() void {
    buggedd.log(.info, "hello 42", @src());
    buggedd.log(.error, "something broke", @src());
}
```

```zig
// Optional: log to file
try buggedd.setLogFile("/tmp/app.log");
```

```
zig build-exe main.zig buggedd.zig
```

---

<a name="asm"></a>
## x86-64 Assembly (Linux, NASM)  (`asm/buggedd.asm`)

```asm
%include "buggedd.asm"

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
%include "buggedd.asm"
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
