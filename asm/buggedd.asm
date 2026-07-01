; Copyright (c) 2026, Kairav Dutta (@ka1rav6)
;
; This is free and unencumbered software released into the public domain,
; except that the above copyright notice must be retained in all copies
; of this software, in source or binary form.  That's the only requirement.
;
; x86-64 Linux — single-file include for NASM.
;
; Usage:
;   %include "buggedd.asm"
;
;   log_init            ; call once at program start
;   log_trace "msg"
;   log_info  "msg"
;   log_warn  "msg"
;   log_error "msg"
;   log_fatal "msg"     ; exits program
;   log_close           ; call at program end if file logging used
;
; To log to a file instead of terminal, define LOG_FILE_PATH:
;   %define LOG_FILE_PATH "/tmp/app.log"
;   %include "buggedd.asm"

%ifndef BUGGEDD_ASM
%define BUGGEDD_ASM

section .data
log_fd:    dq 0        ; 0 = terminal, otherwise file descriptor

%ifdef LOG_FILE_PATH
log_path:  db LOG_FILE_PATH, 0
%endif

section .text

log_init:
%ifdef LOG_FILE_PATH
    mov rdi, log_path
    mov rsi, 0x441
    mov rdx, 0o644
    mov rax, 2
    syscall
    test rax, rax
    js .done
    mov [log_fd], rax
.done:
%endif
    ret

log_close:
    mov rdi, [log_fd]
    test rdi, rdi
    jz .done
    mov rax, 3
    syscall
.done:
    ret

; rdi=level(0-4), rsi=msg addr, rdx=msg len
log_write:
    push rbp
    mov rbp, rsp

    mov r8, [log_fd]
    test r8, r8
    jz .use_terminal

    ; write to file
    mov rdi, r8
    mov rax, 1
    syscall
    jmp .done

.use_terminal:
    ; choose fd: 1=stdout, 2=stderr
    mov rdi, 1
    cmp rdi, 3
    jl .do_write
    mov rdi, 2
.do_write:
    mov rax, 1
    syscall

.done:
    pop rbp
    ret

; ----------------------------------------------------------------
; Macros
; String literals must end with `len:` label for length calculation.
; Use the helper `log_str` to define a string with its length.
; ----------------------------------------------------------------
; log_str(name, text) — defines name: db text, 10  and  name.len: equ $ - name - 1
%macro log_str 2
%1: db %2, 10
%1.len: equ $ - %1 - 1
%endmacro

; log_trace strlit  — log a TRACE string literal
%macro log_trace 1
    mov rdi, 0
    lea rsi, [%1]
    mov rdx, %1.len
    call log_write
%endmacro

%macro log_info 1
    mov rdi, 1
    lea rsi, [%1]
    mov rdx, %1.len
    call log_write
%endmacro

%macro log_warn 1
    mov rdi, 2
    lea rsi, [%1]
    mov rdx, %1.len
    call log_write
%endmacro

%macro log_error 1
    mov rdi, 3
    lea rsi, [%1]
    mov rdx, %1.len
    call log_write
%endmacro

%macro log_fatal 1
    mov rdi, 4
    lea rsi, [%1]
    mov rdx, %1.len
    call log_write
    mov rax, 60
    xor rdi, rdi
    syscall
%endmacro

%endif
