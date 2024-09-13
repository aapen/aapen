# AApen Register Conventions

Borrowed from [cheatsheet](https://dede.dev/posts/ARM64-Calling-Convention-Cheat-Sheet/)

There are 31 general-purpose registers, labeled X0 to X30. 
The 32nd register is the stack pointer, SP.

 * X0 - X7: Used for parameter passing and return values. If a function has more than 8 arguments, the subsequent ones are passed on the stack.
 * X8: Used as an indirect result location register.
 * X9 - X15: Temporary registers. Can be used freely within a function.
 * X16 - X17: Used as intra-procedure-call scratch registers (temporary).
 * X18: Platform register (OS-reserved).
 * X19 - X28: Callee-saved registers. Functions must save and restore these registers if used.
 * X29: Frame pointer. Used to maintain a reference to the top of the current function’s stack frame.
 * X30: Link register. Holds the return address when a function is called.


In addition, armforth adds these conventions:

 * PSP	.req	x28	    // parameter stack pointer
 * RSP	.req	x29	    // return stack pointer
 * NIP	.req	x10	    // next instruction pointer
  
 * T0	.req	x0	    // caller-saved (our FORTH convention) This seems at odds with the Arm convention above.
 * T0b  .req    w0      // T0 as a short
 * T1	.req	x1
 * T1b  .req    w1      // T1 as a short
 * T2	.req	x2
 * T2b	.req	w2      // T2 as a short
 * T3	.req	x3
 * T3b	.req	w3      // T3 as a short
 * U0	.req	x4	    // callee-saved (our FORTH convention) (conflict?)
 * U0b	.req	w4	    // U0 as a short
 * U1	.req	x5	    // (these were S0-S3 for MIPS-appeal originally)
 * U1b  .req    w5      // U1 as a short
 * U2	.req	x6
 * U2b  .req    w6      // U2 as a short
 * U3	.req	x7
 * U3b  .req    w7      // U3 as a short
