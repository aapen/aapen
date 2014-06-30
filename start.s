@@
@@ pijFORTHos -- Raspberry Pi JonesFORTH Operating System
@@
@@ This code is loaded at 0x00008000 on the Raspberry Pi ARM processor
@@ and is the first code that runs to boot the O/S kernel.
@@
@@ View this file with hard tabs every 8 positions.
@@	|	|	|	|	|			   max width ->
@@      |       |       |       |       |                          max width ->
@@ If your tabs are set correctly, the lines above should be aligned.
@@

@ _start is the kernel bootstrap entry point
	.text
	.align 2
	.global _start
_start:
	sub	sp, pc, #8	@ Bootstrap stack immediately before _start
	mov	r0, sp
	bl	c_start		@ Jump to C entry-point
	bl	jonesforth	@ If c_start returns, call jonesforth...
halt:
	b	halt		@ Full stop

@@
@@ Provide a few assembly-language helpers used by C code, e.g.: raspberry.c
@@
	.text
	.align 2

	.globl NO_OP
NO_OP:			@ void NO_OP();
	bx	lr

	.globl PUT_32
PUT_32:			@ void PUT_32(u32 addr, u32 data);
	str	r1, [r0]
	bx	lr

	.globl GET_32
GET_32:			@ u32 GET_32(u32 addr);
	ldr	r0, [r0]
	bx	lr

	.globl PUT_16
PUT_16:			@ void PUT_32(u32 addr, u16 data);
	strh	r1, [r0]
	bx	lr

	.globl GET_16
GET_16:			@ u16 GET_16(u32 addr);
	ldrh	r0, [r0]
	bx	lr

	.globl PUT_8
PUT_8:			@ void PUT_32(u32 addr, u8 data);
	strb	r1, [r0]
	bx	lr

	.globl GET_8
GET_8:			@ u8 GET_8(u32 addr);
	ldrb	r0, [r0]
	bx	lr

	.globl GET_PC
GET_PC:			@ u32 GET_PC();
	mov	r0,lr
	bx	lr

	.globl BRANCH_TO
BRANCH_TO:		@ void BRANCH_TO(u32 addr);
	bx	r0

	.globl BOOT
BOOT:			@ void BOOT(u32 dst, u32 src, u32 len);
	mov	lr, r0		@ put boot address in link register
	add	r12, pc, #8	@ start address of code to copy
	ldmia	r12, {r3-r10}	@ read 8 words of code
	stmdb	sp!, {r3-r10}	@ copy code onto stack
	bx	sp		@ jump to code on the stack!
1:	ldmia	r1!, {r3-r10}	@ read 8 words
	stmia	r0!, {r3-r10}	@ write 8 words
	subs	r2, #32		@ decrement len
	bgt	1b		@ more to copy?
	bx	lr		@ if not, jump to new kernel
	.int 	0x00000000	@ padding...
	.byte	0xB0, 0x07, 0x10, 0xAD
	.int 	0x00000000	@ padding...
