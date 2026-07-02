; Test program for logx.asm
; Assemble from project root:
;   nasm -felf64 test/asm/test_logx.asm -I asm/ -o /tmp/test_logx_asm.o
;   ld /tmp/test_logx_asm.o -o /tmp/test_logx_asm
;   ./test_logx_asm

%include "logx.asm"

section .data
    log_str trace_msg, "TRACE test message"
    log_str info_msg,  "INFO test message"
    log_str warn_msg,  "WARN test message"
    log_str error_msg, "ERROR test message"

section .text
global _start

_start:
    call log_init

    log_trace trace_msg
    log_info  info_msg
    log_warn  warn_msg
    log_error error_msg

    call log_close

    mov rax, 60
    xor rdi, rdi
    syscall
