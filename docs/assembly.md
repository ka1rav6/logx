# LogX for x86-64 Assembly

Single-file logger for NASM on Linux. Raw syscalls only — no libc, nothing to
link.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [`log_init` and the stack](#log_init-and-the-stack)
- [API reference](#api-reference)
- [Logging numbers](#logging-numbers)
- [Registers and flags](#registers-and-flags)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Assembler | NASM 2.13+ (for `__?FILE?__`, `__?LINE?__`, `__?SECT?__`) |
| Platform | x86-64 Linux only |
| Linking | Nothing. No libc. |

## Install

Copy `asm/logx.asm` into your project and `%include` it.

```bash
nasm -felf64 main.asm -o main.o && ld main.o -o main
```

Point NASM at the directory if you keep it elsewhere:

```bash
nasm -felf64 main.asm -I third_party/logx/ -o main.o
```

## Quick start

```asm
%include "logx.asm"

section .text
global _start
_start:
    log_init                            ; must be the FIRST instruction

    log_trace("starting up")
    log_info("listening on port 8080")
    log_warn("memory is high")
    log_error("connection lost")

    log_exit 0
```

```
[08:53:01.042][TRACE] main.asm:8 -> starting up
[08:53:01.042][INFO ] main.asm:9 -> listening on port 8080
[08:53:01.043][WARN ] main.asm:10 -> memory is high
[08:53:01.043][ERROR] main.asm:11 -> connection lost
```

The file and line come from NASM's `__?FILE?__` and `__?LINE?__`, so they are
the real call site with nothing to pass in.

### Why the parentheses

`log_info("...")` is a single-line `%define`, not a `%macro`. Only single-line
macros expand `__?FILE?__` and `__?LINE?__` in the *caller's* context; a
`%macro` would report `logx.asm` and a line inside it, which is useless.

`log_init` and `log_exit` need no call site, so they stay parameter-style
without parentheses. That inconsistency is deliberate and is the price of
getting real line numbers.

## `log_init` and the stack

`log_init` reads the environment off the initial process stack. At `_start`,
`rsp` points at `argc`, with `argv` and then `envp` above it — but only until
something pushes. So:

**`log_init` must be the first instruction in `_start`.**

```asm
_start:
    log_init            ; correct

_start:
    push rbp            ; rsp has moved
    log_init            ; now reads garbage
```

Logging works without `log_init` — you just get no environment handling, so
`LOG_LEVEL` and friends are ignored and the defaults apply.

### Starting from `main` under libc

If you link against libc and start at `main`, there is no reliable initial
stack to read. Skip `log_init` and set the state directly:

```asm
    mov byte [log_min_level], LOG_WARN
    mov byte [log_use_color], 1
    mov byte [log_sink], LOG_SINK_STDERR
```

## API reference

### Logging macros

| Macro | Level |
|---|---|
| `log_trace("...")` | TRACE |
| `log_info("...")` | INFO |
| `log_warn("...")` | WARN |
| `log_error("...")` | ERROR |
| `log_fatal("...")` | FATAL — writes, then exits with status 1 |
| `log_msg(LEVEL)` | a runtime string in `rsi`/`rdx` |

Each takes a string literal **or** a label defined with `log_str`:

```asm
section .data
log_str greeting, "hello from a label"

section .text
    log_info("an inline literal")
    log_info(greeting)
```

### Setup and teardown macros

| Macro | Purpose |
|---|---|
| `log_init` | Read the environment. First instruction in `_start`. |
| `log_exit status` | Close the log file and exit with `status`. |
| `log_str name, "text"` | Define a reusable string plus `name.len`. |

### Functions

Called with `call`, following the SysV argument registers.

| Function | Arguments | Returns |
|---|---|---|
| `log_set_file` | `rdi` = NUL-terminated path | `rax` = 0, or a negative errno |
| `log_close` | — | — |
| `log_u64` | `rdi` = value, `rsi` = destination | `rax` = digit count |
| `log_u64_pad` | `rdi` = value, `rsi` = destination, `rdx` = width | — |
| `log_basename` | `rdi` = path | `rax` = pointer past the last `/` |
| `log_strlen` | `rdi` = NUL-terminated string | `rax` = length |
| `log_isatty` | `rdi` = fd | `rax` = 1 or 0 |

### State variables

Write to these directly; there is no setter function.

| Variable | Size | Meaning |
|---|---|---|
| `log_min_level` | byte | Messages below this are dropped |
| `log_use_color` | byte | 1 to wrap terminal output in ANSI color |
| `log_sink` | byte | `LOG_SINK_SPLIT`, `LOG_SINK_STDOUT`, `LOG_SINK_STDERR` |
| `log_fd` | qword | 0 = terminal, otherwise a file descriptor |
| `log_tz_offset` | qword | Signed seconds to add to UTC |

```asm
    mov byte [log_min_level], LOG_WARN
    mov qword [log_tz_offset], 5 * 3600 + 30 * 60    ; UTC+05:30
```

### Constants

```asm
LOG_TRACE equ 0
LOG_INFO  equ 1
LOG_WARN  equ 2
LOG_ERROR equ 3
LOG_FATAL equ 4
LOG_OFF   equ 5

LOG_SINK_SPLIT  equ 0
LOG_SINK_STDOUT equ 1
LOG_SINK_STDERR equ 2
```

### Compile-time options

```asm
%define LOG_FILE_PATH "/tmp/app.log"    ; before the include
%include "logx.asm"
```

`log_init` then opens that path and logs there instead of the terminal.

## Logging numbers

Assembly has no `printf`, so there is no format-string equivalent. Build the
message yourself and log it with `log_msg`. `log_u64` is exported for exactly
this — it writes decimal digits at `rsi` and returns the count in `rax`:

```asm
section .rodata
prefix:     db "listening on port "
prefix_len: equ $ - prefix

section .bss
msg: resb 64

section .text
    ; copy the prefix
    mov rdi, prefix
    mov rsi, msg
    mov rcx, prefix_len
.copy:
    mov al, [rdi]
    mov [rsi], al
    inc rdi
    inc rsi
    dec rcx
    jnz .copy

    ; append the number
    mov rdi, 8080
    call log_u64                ; digits at rsi, count in rax
    add rsi, rax

    ; log the assembled buffer
    lea rdx, [msg]
    sub rsi, rdx                ; rsi - msg = total length
    mov rdx, rsi
    lea rsi, [msg]
    log_msg(LOG_INFO)
```

```
[08:53:01.042][INFO ] main.asm:35 -> listening on port 8080
```

`log_u64_pad` is the fixed-width variant, used internally for the timestamp:

```asm
    mov rdi, 7                  ; value
    mov rsi, buf                ; destination
    mov rdx, 3                  ; width
    call log_u64_pad            ; writes "007"
```

Neither handles negative numbers. Print the sign yourself and pass the
magnitude.

## Registers and flags

**The log macros preserve every register and the flags.** All sixteen
general-purpose registers, including the callee-saved `rbx`, `rbp` and
`r12`–`r15`, plus `rflags` via `pushfq`. That is what makes them safe to drop
into the middle of existing code:

```asm
    mov rax, 0x1234
    cmp rbx, rcx
    log_info("about to branch")     ; clobbers nothing
    je .equal                       ; the flags from the cmp still hold
```

The macros do use the stack — under 200 bytes: 16 pushed qwords for the
registers and flags, plus a 32-byte `timespec` scratch area. Do not log while
`rsp` points at something you still need.

The `call`ed functions (`log_u64`, `log_set_file`, …) follow the ordinary SysV
convention and **do** clobber the scratch registers. Save what you need around
them.

## Recipes

### Log to a file at runtime

```asm
section .rodata
path: db "/tmp/app.log", 0

section .text
    lea rdi, [path]
    call log_set_file
    test rax, rax
    js .could_not_open

    log_info("this goes to the file")
    call log_close                  ; back to the terminal
```

### Filter by level without the environment

```asm
    mov byte [log_min_level], LOG_WARN
    log_info("dropped")
    log_warn("kept")
```

### Local timestamps

```asm
    mov qword [log_tz_offset], 5 * 3600 + 30 * 60    ; UTC+05:30
    mov qword [log_tz_offset], -8 * 3600             ; UTC-08:00
```

### Everything to stderr

```asm
    mov byte [log_sink], LOG_SINK_STDERR
```

Or `LOG_STREAM=stderr` in the environment, if you called `log_init`.

### A reusable message

```asm
section .data
log_str msg_retry, "retrying the connection"

section .text
    log_warn(msg_retry)
```

`log_str` defines both the bytes and `msg_retry.len`, which is what the
label form of the macros reads.

## Gotchas

**`log_init` must be the first instruction in `_start`.** See
[`log_init` and the stack](#log_init-and-the-stack).

**The logging macros need parentheses**, `log_exit` does not. See
[Why the parentheses](#why-the-parentheses).

**No format strings.** See [Logging numbers](#logging-numbers).

**Messages are capped at 1024 bytes** (`LOGX_BUF_MAX`), including the
timestamp, level and location. Longer messages are truncated.

**Timestamps are UTC** unless you set `log_tz_offset`.

**`log_fatal` exits with status 1** after closing the log file. `log_exit 0`
is the normal path.

**x86-64 Linux only.** The syscall numbers, the `ioctl` TTY probe, and the
initial-stack layout are all Linux and all 64-bit.

**`log_u64` clobbers scratch registers.** It is a `call`, not a macro.

**The internal label namespace is `log_`.** Do not define your own `log_u64`,
`log_write`, `log_init_impl` and so on. Your `_start`-local labels are fine —
the file uses `.`-prefixed local labels internally.

## Troubleshooting

**Timestamps are `00:00:00.000` or nonsense** — `log_init` was not the first
instruction in `_start`, so it read a stack that had already moved. It only
affects the environment; move `log_init` up.

**`LOG_LEVEL` is ignored** — you did not call `log_init`, or it was not first.

**`error: parser: instruction expected`** on a `log_info` line — you wrote it
without parentheses. It is `log_info("...")`.

**`symbol 'xyz.len' undefined`** — you passed a bare label that was not
defined with `log_str`. Either use `log_str`, or set `rsi`/`rdx` yourself and
use `log_msg`.

**The file and line say `logx.asm`** — you are on an old copy that used
`%macro` for the log entry points. Current versions use `%define`.

**Garbage or a crash after a log call** — you logged while `rsp` pointed at
data you still needed. The macros use under 200 bytes of stack.

**No color** — a pipe is not a terminal, so auto-detection correctly turns it
off. Use `LOG_COLOR=1`, or `mov byte [log_use_color], 1`.

**Nothing is written at all** — check `log_min_level`; `LOG_LEVEL=OFF` or
`LOG_OFF` silences everything.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`asm/logx.asm`](../asm/logx.asm) — the source
- [`test/asm/test_logx.asm`](../test/asm/test_logx.asm) and
  [`test/asm/check.sh`](../test/asm/check.sh) — worked examples
