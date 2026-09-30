; Tests for asm/logx.asm. Build and run from the project root:
;   nasm -felf64 test/asm/test_logx.asm -I asm/ -o /tmp/test_logx_asm.o
;   ld /tmp/test_logx_asm.o -o /tmp/test_logx_asm
;   /tmp/test_logx_asm
;
; Exits 0 when every check passes, 2 when a register was clobbered.
; The output shape is checked by test/asm/check.sh, which runs this program
; under a few different environments and greps what comes out.

%include "logx.asm"

section .data
log_str reusable, "a reusable string"

section .rodata
runtime_text: db "built at runtime"
runtime_len:  equ $ - runtime_text

section .text
global _start

_start:
    log_init                        ; must be first: it reads envp off the stack

    ; Fill every register the SysV ABI lets a callee clobber, plus the
    ; callee-saved ones, and confirm the log macros leave all of them alone.
    mov rax, 0x1111
    mov rbx, 0x2222
    mov rcx, 0x3333
    mov rdx, 0x4444
    mov rsi, 0x5555
    mov rdi, 0x6666
    mov rbp, 0x7777
    mov r8,  0x8888
    mov r9,  0x9999
    mov r10, 0xAAAA
    mov r11, 0xBBBB
    mov r12, 0xCCCC
    mov r13, 0xDDDD
    mov r14, 0xEEEE
    mov r15, 0xFFFF

    log_trace("trace msg")
    log_info("port 8080")
    log_warn("memory is high")
    log_error("lost: ECONNRESET")
    log_info(reusable)

    cmp rax, 0x1111
    jne .clobbered
    cmp rbx, 0x2222
    jne .clobbered
    cmp rcx, 0x3333
    jne .clobbered
    cmp rdx, 0x4444
    jne .clobbered
    cmp rsi, 0x5555
    jne .clobbered
    cmp rdi, 0x6666
    jne .clobbered
    cmp rbp, 0x7777
    jne .clobbered
    cmp r8, 0x8888
    jne .clobbered
    cmp r9, 0x9999
    jne .clobbered
    cmp r10, 0xAAAA
    jne .clobbered
    cmp r11, 0xBBBB
    jne .clobbered
    cmp r12, 0xCCCC
    jne .clobbered
    cmp r13, 0xDDDD
    jne .clobbered
    cmp r14, 0xEEEE
    jne .clobbered
    cmp r15, 0xFFFF
    jne .clobbered

    log_info("registers preserved")

    ; A string assembled at runtime, rather than a literal.
    lea rsi, [runtime_text]
    mov rdx, runtime_len
    log_msg(LOG_INFO)

    log_exit 0

.clobbered:
    log_error("REGISTER CLOBBERED")
    log_exit 2
