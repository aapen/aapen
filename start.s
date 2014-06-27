
@ _start is the kernel bootstrap entry point
        .text
        .align 4
        .global _start
_start:
	sub	sp, pc, #12	@ Bootstrap stack immediately before _start
	mov	r0, sp
	bl	c_start		@ Jump to C entry-point

@@
@@ Provide a few assembly-language helpers used by C code, e.g.: raspberry.c
@@
        .text
        .align 4

        .globl NO_OP
NO_OP:
        bx lr

        .globl PUT_32
PUT_32:
        str r1,[r0]
        bx lr

        .globl GET_32
GET_32:
        ldr r0,[r0]
        bx lr

        .globl PUT_16
PUT_16:
        strh r1,[r0]
        bx lr

        .globl PUT_8
PUT_8:
        strb r1,[r0]
        bx lr

        .globl GET_PC
GET_PC:
        mov r0,lr
        bx lr

        .globl BRANCH_TO
BRANCH_TO:
        bx r0

