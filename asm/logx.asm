; Copyright (c) 2026, Kairav Dutta (@ka1rav6)
;
; This is free and unencumbered software released into the public domain,
; except that the above copyright notice must be retained in all copies
; of this software, in source or binary form.  That's the only requirement.
;
; logx.asm -- single-file logger for x86-64 Linux, NASM syntax.
; Raw syscalls only: no libc, nothing to link.
;
;   %include "logx.asm"
;
;   section .text
;   global _start
;   _start:
;       log_init                        ; must be the FIRST thing in _start
;       log_info("listening")
;       log_warn("memory is high")
;       log_error("connection lost")
;       log_fatal("unrecoverable")      ; writes, then exits with status 1
;       log_exit 0
;
; Output matches the other languages:
;
;   [HH:MM:SS.mmm][INFO ] myprog.asm:12 -> listening
;
; The file and line come from NASM's __?FILE?__ and __?LINE?__, so they are the
; real call site with nothing to pass in.
;
; ---------------------------------------------------------------------------
; log_init
; ---------------------------------------------------------------------------
; log_init is a macro, not a function, and it reads the environment off the
; initial stack. That only works while rsp still points at argc, which is why it
; has to be the first instruction in _start, before anything is pushed.
;
; Linking against libc and starting from main instead? Skip log_init and set
; log_min_level / log_use_color yourself:
;
;   mov byte [log_min_level], LOG_WARN
;   mov byte [log_use_color], 1
;
; ---------------------------------------------------------------------------
; Logging runtime strings
; ---------------------------------------------------------------------------
; The macros above take string literals. For a buffer you built yourself:
;
;   lea  rsi, [my_buffer]
;   mov  rdx, my_length
;   log_msg(LOG_INFO)               ; picks up the call site for you
;
; ---------------------------------------------------------------------------
; Registers
; ---------------------------------------------------------------------------
; The log macros preserve every register, including the SysV scratch set and
; the flags, so they are safe to drop into the middle of existing code.
;
; ---------------------------------------------------------------------------
; Options and environment
; ---------------------------------------------------------------------------
;   %define LOG_FILE_PATH "/tmp/app.log"   ; before the include: log to a file
;
;   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
;   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
;   NO_COLOR    set to anything to disable color
;   LOG_STREAM  split (default) | stdout | stderr
;
; Timestamps are UTC; there is no time-zone database without libc. Set
; log_tz_offset (a signed count of seconds) for a fixed local offset:
;
;   mov qword [log_tz_offset], 5 * 3600 + 30 * 60

%ifndef LOGX_ASM
%define LOGX_ASM

LOG_TRACE equ 0
LOG_INFO  equ 1
LOG_WARN  equ 2
LOG_ERROR equ 3
LOG_FATAL equ 4
LOG_OFF   equ 5

LOG_SINK_SPLIT  equ 0
LOG_SINK_STDOUT equ 1
LOG_SINK_STDERR equ 2

%define LOGX_SYS_WRITE         1
%define LOGX_SYS_OPEN          2
%define LOGX_SYS_CLOSE         3
%define LOGX_SYS_CLOCK_GETTIME 228
%define LOGX_SYS_EXIT          60

; O_WRONLY | O_CREAT | O_APPEND
%define LOGX_OPEN_FLAGS 0o2101
%define LOGX_OPEN_MODE  0o644

%define LOGX_BUF_MAX 1024

; ---------------------------------------------------------------------------
section .rodata

log_names:                          ; five bytes each, padded so columns align
    db "TRACE", "INFO ", "WARN ", "ERROR", "FATAL"
log_colors:                         ; five bytes each: ESC [ 3 x m
    db 27, "[36m", 27, "[32m", 27, "[33m", 27, "[31m", 27, "[35m"
log_reset:      db 27, "[0m"
log_reset_len:  equ $ - log_reset
log_arrow:      db " -> "
log_arrow_len:  equ $ - log_arrow

log_env_level:  db "LOG_LEVEL=", 0
log_env_color:  db "LOG_COLOR=", 0
log_env_nocol:  db "NO_COLOR=", 0
log_env_stream: db "LOG_STREAM=", 0

%ifdef LOG_FILE_PATH
log_path:       db LOG_FILE_PATH, 0
%endif

; ---------------------------------------------------------------------------
section .data

log_min_level:  db LOG_TRACE        ; messages below this are dropped
log_use_color:  db 0
log_sink:       db LOG_SINK_SPLIT
log_fd:         dq 0                ; 0 = terminal, otherwise a file descriptor
log_tz_offset:  dq 0                ; seconds to add to UTC

; ---------------------------------------------------------------------------
section .bss

log_buf:    resb LOGX_BUF_MAX
log_ts:     resb 16

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; log_init_impl -- rdi = pointer to argc on the initial stack.
; Walks past argv to reach envp, then reads the variables we care about.
; ---------------------------------------------------------------------------
log_init_impl:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11

    mov rax, [rdi]                  ; argc
    lea rbx, [rdi + 8 + rax*8]      ; past argv[0..argc-1]
    add rbx, 8                      ; past the NULL that terminates argv
                                    ; rbx = envp

%ifdef LOG_FILE_PATH
    mov rdi, log_path
    mov rsi, LOGX_OPEN_FLAGS
    mov rdx, LOGX_OPEN_MODE
    mov rax, LOGX_SYS_OPEN
    syscall
    test rax, rax
    js .no_file
    mov [log_fd], rax
.no_file:
%endif

    ; LOG_STREAM
    mov rdi, rbx
    mov rsi, log_env_stream
    call log_env_find
    test rax, rax
    jz .after_stream
    mov rdi, rax
    call log_parse_stream
    mov [log_sink], al
.after_stream:

    ; LOG_LEVEL
    mov rdi, rbx
    mov rsi, log_env_level
    call log_env_find
    test rax, rax
    jz .after_level
    mov rdi, rax
    call log_parse_level
    mov [log_min_level], al
.after_level:

    ; LOG_COLOR wins over NO_COLOR, which wins over auto-detection.
    mov rdi, rbx
    mov rsi, log_env_color
    call log_env_find
    test rax, rax
    jz .try_nocolor
    mov rdi, rax
    call log_parse_bool
    cmp al, 2                       ; 2 = not a recognised value
    je .try_nocolor
    mov [log_use_color], al
    jmp .done

.try_nocolor:
    mov rdi, rbx
    mov rsi, log_env_nocol
    call log_env_find
    test rax, rax
    jnz .done                       ; NO_COLOR present: leave color off

    ; Auto-detect: a terminal is what we colorise for, and without libc the
    ; cheapest honest check is whether the target fd is a tty.
    movzx eax, byte [log_sink]
    cmp al, LOG_SINK_STDERR
    je .probe_stderr
    cmp al, LOG_SINK_STDOUT
    je .probe_stdout
    mov rdi, 1
    call log_isatty
    test rax, rax
    jz .done
    mov rdi, 2
    call log_isatty
    test rax, rax
    jz .done
    mov byte [log_use_color], 1
    jmp .done
.probe_stdout:
    mov rdi, 1
    call log_isatty
    mov [log_use_color], al
    jmp .done
.probe_stderr:
    mov rdi, 2
    call log_isatty
    mov [log_use_color], al

.done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ---------------------------------------------------------------------------
; log_isatty -- rdi = fd. Returns 1 in al if it is a terminal, else 0.
; ioctl(fd, TCGETS, buf): succeeds only on a tty.
; ---------------------------------------------------------------------------
log_isatty:
    sub rsp, 64
    mov rsi, 0x5401                 ; TCGETS
    mov rdx, rsp
    mov rax, 16                     ; ioctl
    syscall
    add rsp, 64
    test rax, rax
    jns .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; ---------------------------------------------------------------------------
; log_env_find -- rdi = envp, rsi = "NAME=" (NUL-terminated).
; Returns the value pointer in rax, or 0 when the variable is absent.
; ---------------------------------------------------------------------------
log_env_find:
.next:
    mov r8, [rdi]
    test r8, r8
    jz .missing
    mov r9, rsi                     ; r9 walks the prefix
    mov r10, r8                     ; r10 walks the entry
.compare:
    mov al, [r9]
    test al, al
    jz .found                       ; prefix exhausted: this is our variable
    mov cl, [r10]
    cmp al, cl
    jne .advance
    inc r9
    inc r10
    jmp .compare
.advance:
    add rdi, 8
    jmp .next
.found:
    mov rax, r10                    ; just past the '='
    ret
.missing:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; log_streq_ci -- rdi = NUL-terminated string, rsi = NUL-terminated pattern.
; Case-insensitive. Returns 1 in al on a match, else 0.
; ---------------------------------------------------------------------------
log_streq_ci:
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    ; fold both to lower case
    cmp al, 'A'
    jb .a_done
    cmp al, 'Z'
    ja .a_done
    add al, 32
.a_done:
    cmp cl, 'A'
    jb .b_done
    cmp cl, 'Z'
    ja .b_done
    add cl, 32
.b_done:
    cmp al, cl
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; log_parse_level -- rdi = value string. Returns the level in al.
; ---------------------------------------------------------------------------
log_parse_level:
    push rdi
%macro logx_try_level 2
    pop rdi
    push rdi
    mov rsi, %%pat
    call log_streq_ci
    test al, al
    jz %%skip
    pop rdi
    mov eax, %2
    ret
%%skip:
    [section .rodata]
%%pat: db %1, 0
    __?SECT?__
%endmacro

    logx_try_level "TRACE", LOG_TRACE
    logx_try_level "DEBUG", LOG_TRACE
    logx_try_level "ALL",   LOG_TRACE
    logx_try_level "0",     LOG_TRACE
    logx_try_level "INFO",  LOG_INFO
    logx_try_level "1",     LOG_INFO
    logx_try_level "WARN",  LOG_WARN
    logx_try_level "WARNING", LOG_WARN
    logx_try_level "2",     LOG_WARN
    logx_try_level "ERROR", LOG_ERROR
    logx_try_level "ERR",   LOG_ERROR
    logx_try_level "3",     LOG_ERROR
    logx_try_level "FATAL", LOG_FATAL
    logx_try_level "CRITICAL", LOG_FATAL
    logx_try_level "4",     LOG_FATAL
    logx_try_level "OFF",   LOG_OFF
    logx_try_level "NONE",  LOG_OFF
    logx_try_level "SILENT", LOG_OFF
    logx_try_level "5",     LOG_OFF

    pop rdi
    mov eax, LOG_TRACE              ; unrecognised: keep the default
    ret

; ---------------------------------------------------------------------------
; log_parse_bool -- rdi = value string. 1 true, 0 false, 2 unrecognised.
; ---------------------------------------------------------------------------
log_parse_bool:
    push rdi
%macro logx_try_bool 2
    pop rdi
    push rdi
    mov rsi, %%pat
    call log_streq_ci
    test al, al
    jz %%skip
    pop rdi
    mov eax, %2
    ret
%%skip:
    [section .rodata]
%%pat: db %1, 0
    __?SECT?__
%endmacro

    logx_try_bool "1",     1
    logx_try_bool "true",  1
    logx_try_bool "yes",   1
    logx_try_bool "on",    1
    logx_try_bool "0",     0
    logx_try_bool "false", 0
    logx_try_bool "no",    0
    logx_try_bool "off",   0

    pop rdi
    mov eax, 2
    ret

; ---------------------------------------------------------------------------
; log_parse_stream -- rdi = value string. Returns a LOG_SINK_* value in al.
; ---------------------------------------------------------------------------
log_parse_stream:
    push rdi
    mov rsi, .pat_stdout
    call log_streq_ci
    test al, al
    jz .not_stdout
    pop rdi
    mov eax, LOG_SINK_STDOUT
    ret
.not_stdout:
    pop rdi
    push rdi
    mov rsi, .pat_stderr
    call log_streq_ci
    test al, al
    jz .split
    pop rdi
    mov eax, LOG_SINK_STDERR
    ret
.split:
    pop rdi
    mov eax, LOG_SINK_SPLIT
    ret
    [section .rodata]
.pat_stdout: db "stdout", 0
.pat_stderr: db "stderr", 0
    __?SECT?__

; ---------------------------------------------------------------------------
; log_u64_pad -- rdi = value, rsi = destination, rdx = digit count.
; Writes exactly rdx zero-padded decimal digits.
; ---------------------------------------------------------------------------
log_u64_pad:
    mov rax, rdi
    lea rcx, [rsi + rdx - 1]        ; fill from the last digit backwards
    mov r8, 10
.next:
    xor rdx, rdx
    div r8                          ; rax = quotient, rdx = remainder
    add dl, '0'
    mov [rcx], dl
    dec rcx
    cmp rcx, rsi
    jae .next
    ret

; ---------------------------------------------------------------------------
; log_u64 -- rdi = value, rsi = destination. Returns the digit count in rax.
; ---------------------------------------------------------------------------
log_u64:
    mov rax, rdi
    mov r9, rsi
    sub rsp, 32
    mov rcx, rsp
    add rcx, 31
    mov r8, 10
    xor r10, r10                    ; digit count
.next:
    xor rdx, rdx
    div r8
    add dl, '0'
    mov [rcx], dl
    dec rcx
    inc r10
    test rax, rax
    jnz .next
    ; copy the digits out, most significant first
    inc rcx
    mov rdx, r10
.copy:
    mov al, [rcx]
    mov [r9], al
    inc rcx
    inc r9
    dec rdx
    jnz .copy
    add rsp, 32
    mov rax, r10
    ret

; ---------------------------------------------------------------------------
; log_timestamp -- fills log_ts with "HH:MM:SS.mmm" (12 bytes).
; ---------------------------------------------------------------------------
log_timestamp:
    sub rsp, 32
    xor edi, edi                    ; CLOCK_REALTIME
    mov rsi, rsp
    mov rax, LOGX_SYS_CLOCK_GETTIME
    syscall

    mov r11, [rsp]                  ; tv_sec
    mov r10, [rsp + 8]              ; tv_nsec
    add rsp, 32

    add r11, [log_tz_offset]

    ; seconds within the day, with a floored modulo so a negative offset
    ; near midnight still lands inside 0..86399
    mov rax, r11
    mov rcx, 86400
    cqo
    idiv rcx                        ; rdx = remainder, sign follows rax
    test rdx, rdx
    jns .positive
    add rdx, rcx
.positive:
    mov r11, rdx                    ; r11 = seconds of day

    mov rax, r11
    xor rdx, rdx
    mov rcx, 3600
    div rcx
    mov r8, rax                     ; hours
    mov r9, rdx                     ; leftover seconds

    mov rax, r9
    xor rdx, rdx
    mov rcx, 60
    div rcx                         ; rax = minutes, rdx = seconds

    mov rdi, r8
    mov rsi, log_ts
    mov rdx, 2
    push rax
    call log_u64_pad
    pop rax
    mov byte [log_ts + 2], ':'

    mov rdi, rax
    mov rsi, log_ts + 3
    mov rdx, 2
    call log_u64_pad
    mov byte [log_ts + 5], ':'

    ; recompute the seconds field; the divisions above clobbered rdx
    mov rax, r11
    xor rdx, rdx
    mov rcx, 60
    div rcx
    mov rdi, rdx
    mov rsi, log_ts + 6
    mov rdx, 2
    call log_u64_pad
    mov byte [log_ts + 8], '.'

    mov rax, r10                    ; nanoseconds to milliseconds
    xor rdx, rdx
    mov rcx, 1000000
    div rcx
    mov rdi, rax
    mov rsi, log_ts + 9
    mov rdx, 3
    call log_u64_pad
    ret

; ---------------------------------------------------------------------------
; log_append -- rdi = source, rsi = length, rbx = write cursor.
; Advances rbx and refuses to run past the end of log_buf.
; ---------------------------------------------------------------------------
log_append:
    test rsi, rsi
    jz .done
    lea rax, [log_buf + LOGX_BUF_MAX - 2]
    mov rcx, rax
    sub rcx, rbx                    ; bytes still free
    jbe .done
    cmp rsi, rcx
    jbe .copy
    mov rsi, rcx                    ; truncate rather than overflow
.copy:
    mov rcx, rsi
.loop:
    mov al, [rdi]
    mov [rbx], al
    inc rdi
    inc rbx
    dec rcx
    jnz .loop
.done:
    ret

; ---------------------------------------------------------------------------
; log_write -- rdi = level, rsi = message, rdx = message length,
;              r8 = file name (NUL-terminated), r10d = line number.
; Assembles the whole record and emits it with a single write().
; ---------------------------------------------------------------------------
log_write:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push rbp
    push r12
    push r13
    push r14
    push r15
    pushfq

    movzx eax, byte [log_min_level]
    cmp al, LOG_OFF
    jae .finish
    cmp edi, eax
    jb .finish

    mov r12, rdi                    ; level
    mov r13, rsi                    ; message
    mov r14, rdx                    ; message length
    mov r15, r8                     ; file name
    mov ebp, r10d                   ; line number

    call log_timestamp

    mov rbx, log_buf                ; rbx is the cursor from here on

    ; color prefix, but never into a file
    cmp qword [log_fd], 0
    jne .no_color
    cmp byte [log_use_color], 0
    je .no_color
    mov rax, r12
    lea rdi, [log_colors + rax*4]
    add rdi, rax                    ; five bytes per entry
    mov rsi, 5
    call log_append
.no_color:

    mov rdi, .lbracket
    mov rsi, 1
    call log_append
    mov rdi, log_ts
    mov rsi, 12
    call log_append
    mov rdi, .rb_lb                 ; "]["
    mov rsi, 2
    call log_append

    mov rax, r12
    lea rdi, [log_names + rax*4]
    add rdi, rax                    ; five bytes per entry
    mov rsi, 5
    call log_append

    mov rdi, .rb_sp                 ; "] "
    mov rsi, 2
    call log_append

    mov rdi, r15                    ; file name, reduced to its base name
    call log_basename
    mov r15, rax
    mov rdi, r15
    call log_strlen
    mov rdi, r15
    mov rsi, rax
    call log_append

    mov rdi, .colon
    mov rsi, 1
    call log_append

    mov rdi, rbp
    mov rsi, rbx
    call log_u64                    ; writes straight into the buffer
    add rbx, rax

    mov rdi, log_arrow
    mov rsi, log_arrow_len
    call log_append

    mov rdi, r13
    mov rsi, r14
    call log_append

    cmp qword [log_fd], 0
    jne .newline
    cmp byte [log_use_color], 0
    je .newline
    mov rdi, log_reset
    mov rsi, log_reset_len
    call log_append
.newline:
    mov rdi, .nl
    mov rsi, 1
    call log_append

    ; one write() for the whole line, so concurrent writers cannot interleave
    mov rdx, rbx
    sub rdx, log_buf                ; length
    mov rsi, log_buf

    mov rdi, [log_fd]
    test rdi, rdi
    jnz .emit

    movzx eax, byte [log_sink]
    cmp al, LOG_SINK_STDOUT
    je .use_stdout
    cmp al, LOG_SINK_STDERR
    je .use_stderr
    cmp r12, LOG_ERROR
    jae .use_stderr
.use_stdout:
    mov rdi, 1
    jmp .emit
.use_stderr:
    mov rdi, 2
.emit:
    mov rax, LOGX_SYS_WRITE
    syscall

.finish:
    popfq
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

    [section .rodata]
.lbracket: db "["
.rb_lb:    db "]["
.rb_sp:    db "] "
.colon:    db ":"
.nl:       db 10
    __?SECT?__

; ---------------------------------------------------------------------------
; log_basename -- rdi = NUL-terminated path. Returns a pointer just past the
; last '/' in rax, so __?FILE?__ prints as a name rather than a full path.
; ---------------------------------------------------------------------------
log_basename:
    mov rax, rdi                    ; best answer so far
    mov rcx, rdi
.scan:
    mov dl, [rcx]
    test dl, dl
    jz .done
    inc rcx
    cmp dl, '/'
    jne .scan
    mov rax, rcx                    ; the byte after the slash
    jmp .scan
.done:
    ret

; ---------------------------------------------------------------------------
; log_strlen -- rdi = NUL-terminated string. Returns the length in rax.
; ---------------------------------------------------------------------------
log_strlen:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; ---------------------------------------------------------------------------
; log_set_file -- rdi = NUL-terminated path. Appends log output there.
; Returns 0 in rax on success, or the negative errno from open().
; ---------------------------------------------------------------------------
log_set_file:
    push rdi
    call log_close
    pop rdi
    mov rsi, LOGX_OPEN_FLAGS
    mov rdx, LOGX_OPEN_MODE
    mov rax, LOGX_SYS_OPEN
    syscall
    test rax, rax
    js .failed
    mov [log_fd], rax
    xor eax, eax
    ret
.failed:
    ret

; ---------------------------------------------------------------------------
; log_close -- closes the log file, sending output back to the terminal.
; ---------------------------------------------------------------------------
log_close:
    mov rdi, [log_fd]
    test rdi, rdi
    jz .done
    mov rax, LOGX_SYS_CLOSE
    syscall
    mov qword [log_fd], 0
.done:
    ret

; ---------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------
;
; The logging macros are called with parentheses -- log_info("...") -- because
; only NASM's single-line macros expand __?FILE?__ and __?LINE?__ in the
; caller's context. A %macro would report logx.asm and its own line instead.
; log_init and log_exit need no call site, so they stay parameter-style.

; Must be the first instruction in _start: it reads envp off the initial stack.
%macro log_init 0
    mov rdi, rsp
    call log_init_impl
%endmacro

; Closes the log file and exits with the given status.
%macro log_exit 1
    call log_close
    mov edi, %1
    mov eax, LOGX_SYS_EXIT
    syscall
%endmacro

; Defines a reusable string plus its length: log_str name, "text"
%macro log_str 2
%1:     db %2
%1.len: equ $ - %1
%endmacro

; level, "literal", file, line
%macro logx_emit_literal 4
    [section .rodata]
%%file: db %3, 0
%%text: db %2
%%len:  equ $ - %%text
    __?SECT?__
    push rdi
    push rsi
    push rdx
    push r8
    push r10
    mov edi, %1
    lea rsi, [%%text]
    mov rdx, %%len
    lea r8, [%%file]
    mov r10d, %4
    call log_write
    pop r10
    pop r8
    pop rdx
    pop rsi
    pop rdi
%endmacro

; level, label (from log_str), file, line
%macro logx_emit_label 4
    [section .rodata]
%%file: db %3, 0
    __?SECT?__
    push rdi
    push rsi
    push rdx
    push r8
    push r10
    mov edi, %1
    lea rsi, [%2]
    mov rdx, %2.len
    lea r8, [%%file]
    mov r10d, %4
    call log_write
    pop r10
    pop r8
    pop rdx
    pop rsi
    pop rdi
%endmacro

%macro logx_dispatch 4
    %ifid %2
        logx_emit_label %1, %2, %3, %4
    %else
        logx_emit_literal %1, %2, %3, %4
    %endif
%endmacro

; level, file, line -- rsi and rdx already hold a runtime string and its length
%macro logx_emit_runtime 3
    [section .rodata]
%%file: db %2, 0
    __?SECT?__
    push rdi
    push rsi
    push rdx
    push r8
    push r10
    mov edi, %1
    lea r8, [%%file]
    mov r10d, %3
    call log_write
    pop r10
    pop r8
    pop rdx
    pop rsi
    pop rdi
%endmacro

%macro logx_emit_fatal 3
    logx_dispatch LOG_FATAL, %1, %2, %3
    call log_close
    mov edi, 1
    mov eax, LOGX_SYS_EXIT
    syscall
%endmacro

; Each takes a string literal or a label defined with log_str:
;   log_info("listening")
;   log_info(reusable_label)
%define log_trace(m) logx_dispatch LOG_TRACE, m, __?FILE?__, __?LINE?__
%define log_info(m)  logx_dispatch LOG_INFO,  m, __?FILE?__, __?LINE?__
%define log_warn(m)  logx_dispatch LOG_WARN,  m, __?FILE?__, __?LINE?__
%define log_error(m) logx_dispatch LOG_ERROR, m, __?FILE?__, __?LINE?__

; Writes the record, then exits with status 1.
%define log_fatal(m) logx_emit_fatal m, __?FILE?__, __?LINE?__

; For a string you built at runtime: set rsi = pointer, rdx = length, then
;   log_msg(LOG_INFO)
%define log_msg(level) logx_emit_runtime level, __?FILE?__, __?LINE?__

%endif
