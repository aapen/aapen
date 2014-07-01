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

	.globl asm_stack
asm_stack:		@ void asm_stack(u32* buf);
	stmia	r0,{r0-r12,lr}	@ save everything in buffer
	bx	lr

	.globl asm_copy32
asm_copy32:		@ void asm_copy32(u32* dst, u32* src, int len);
	push	{r0-r12,lr}	@ save everything on the stack
1:	ldmia	r1!, {r3-r10}	@ read 8 words
	stmia	r0!, {r3-r10}	@ write 8 words
	subs	r2, #32		@ decrement len
	bgt	1b		@ more to copy?
	pop	{r0-r12,pc}	@ restore everything and return

	.globl asm_himem
asm_himem:		@ u32 asm_himem(u32);
	push	{r0-r12,lr}	@ save everything on the stack
@	mov	r11, sp		@ remember where we put everything
	ldr	lr, =0x10000	@ absolute address of "safe" memory
	add	r12, pc, #8	@ start address of code to copy
	ldmia	r12, {r0-r10}	@ read 11 words of code
	stmdb	lr!, {r0-r10}	@ copy code to safe memory
	bx	lr		@ jump to code in safe memory
@ The code we copy to execute from safe memory is as follows:
@	ldmia	r11, {r0-r2}	@ restore dst, src & len
	pop	{r0-r12,pc}	@ restore everything and return
	.byte	0xB0, 0x07, 0x10, 0xAD
	.skip 	32		@ padding...

	.globl asm_safe
asm_safe:		@ u32 asm_safe(u32);
	push	{r0-r12,lr}	@ save everything on the stack
@	mov	r11, sp		@ remember where we put everything
	mov	lr, sp		@ compute jump address in link register
	add	r12, pc, #8	@ start address of code to copy
	ldmia	r12, {r0-r10}	@ read 11 words of code
	stmdb	lr!, {r0-r10}	@ copy code onto the stack
	bx	lr		@ jump to code on the stack!
@ The code we copy to execute from the stack is as follows:
@	ldmia	r11, {r0-r2}	@ restore dst, src & len
	pop	{r0-r12,pc}	@ restore everything and return
	.byte	0xB0, 0x07, 0x10, 0xAD
	.skip 	32		@ padding...

	.globl BOOT
BOOT:			@ void BOOT(u32 len);  // copy and boot new kernel
	ldr	r1, =0x10000	@ absolute address of upload buffer
	mov	r11, r1		@ high-memory code address
	ldr	r2, =0x8000	@ absolute address of kernel memory
	mov	lr, r2		@ kernel entry-point
	add	r12, pc, #8	@ start address of code to copy
	ldmia	r12, {r3-r10}	@ read 8 words of code
	stmdb	r11!, {r3-r10}	@ write 8 words of code
	bx	r11		@ jump to code in high memory
@ This position-independent code executes from high memory
1:	ldmia	r1!, {r3-r10}	@ read 8 words of data
	stmia	r2!, {r3-r10}	@ write 8 words of data
	subs	r0, #32		@ decrement len
	bgt	1b		@ more to copy?
	bx	lr		@ if not, jump to new kernel
	.byte	0xB0, 0x07, 0x10, 0xAD
	.skip 	32		@ padding...

	.globl XBOOT
XBOOT:			@ void XBOOT(u32 dst, u32 src, u32 len);
	push	{r0-r12,lr}	@ save everything on the stack
	mov	r11, sp		@ remember where we put everything
@	mov	lr, r0		@ keep boot address in link register
	add	r12, pc, #8	@ start address of code to copy
	ldmia	r12, {r0-r10}	@ read 11 words of code
	stmdb	sp!, {r0-r10}	@ copy code onto the stack
	bx	sp		@ jump to code on the stack!
@ The code we copy to execute from the stack is as follows:
	ldmia	r11, {r0-r2}	@ restore dst, src & len
1:	ldmia	r1!, {r3-r10}	@ read 8 words
	stmia	r0!, {r3-r10}	@ write 8 words
	subs	r2, #32		@ decrement len
	bgt	1b		@ more to copy?
@	bx	lr		@ if not, jump to new kernel
;	mov	r0, r11		@ dump saved stack frame
;	ldr	r11, =dump256	@ get absolute address of dump routine
;	mov	lr, pc		@ manually calculate link-return address
;	bx	r11		@ call dump routine at absolute address
	pop	{r0-r12,pc}	@ restore everything and return
	.byte	0xB0, 0x07, 0x10, 0xAD
	.skip 	32		@ padding...
