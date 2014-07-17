@@
@@ pijFORTHos -- Raspberry Pi JonesFORTH Operating System
@@
@@ This code is loaded at 0x00008000 on the Raspberry Pi ARM processor
@@ and is the first code that runs to boot the O/S kernel.
@@
@@ View this file with hard tabs every 8 positions.
@@	|	|	.	|	.	.	.	.  max width ->
@@      |       |       .       |       .       .       .       .  max width ->
@@ If your tabs are set correctly, the lines above should be aligned.
@@

@ _start is the bootstrap entry point
	.text
	.align 2
	.global _start
_start:
	sub	r1, pc, #8	@ Where are we?
	mov	sp, r1		@ Bootstrap stack immediately before _start
	ldr	lr, =halt	@ Halt on "return"
	ldr	r0, =0x8000	@ Absolute address of kernel memory
	cmp	r0, r1		@ Are we loaded where we expect to be?
	beq	k_start		@ Then, jump to kernel entry-point
	mov	lr, r0		@ Otherwise, relocate ourselves
	ldr	r2, =0x7F00	@ Copy (32k - 256) bytes
1:	ldmia	r1!, {r3-r10}	@ Read 8 words
	stmia	r0!, {r3-r10}	@ Write 8 words
	subs	r2, #32		@ Decrement len
	bgt	1b		@ More to copy?
	bx	lr		@ Jump to bootstrap entry-point
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

	.globl SPIN
SPIN:			@ void SPIN(u32 count);
	subs	r0, #1		@ decrement count
	bge	SPIN		@ until negative
	bx	lr

	.globl asm_copy32
asm_copy32:		@ void asm_copy32(u32* dst, u32* src, int len);
	push	{r0-r12,lr}	@ save everything on the stack
1:	ldmia	r1!, {r3-r10}	@ read 8 words
	stmia	r0!, {r3-r10}	@ write 8 words
	subs	r2, #32		@ decrement len
	bgt	1b		@ more to copy?
	pop	{r0-r12,pc}	@ restore everything and return

