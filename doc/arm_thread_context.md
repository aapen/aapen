# Thread Context Picture

This is what goes on the stack when a thread is suspended, and what is
loaded back from the stack on rescheduling.

Indexes are in bytes

When saving context:
```
sp - $08: zero fill for alignment
sp - $10: copy of lr (on first context switch to thread, will hold the thread exit fn addr)
sp - $18: lr
sp - $20: fp
sp - $28: x17
sp - $30: x16
sp - $38: x15
sp - $40: x14
sp - $48: x13
sp - $50: x12
sp - $58: x11
sp - $60: x10
sp - $68: x9
sp - $70: x8
sp - $78: x7
sp - $80: x6
sp - $88: x5
sp - $90: x4
sp - $98: x3
sp - $A0: x2
sp - $A8: x1
sp - $B0: x0
sp - $B8: nzcv
sp - $C0: daif
```

When loading context:
```
sp + $B8: zero fill for alignment
sp + $B0: saved pc
sp + $A8: lr
sp + $A0: fp
sp + $98: x17
sp + $90: x16
sp + $88: x15
sp + $80: x14
sp + $78: x13
sp + $70: x12
sp + $68: x11
sp + $60: x10
sp + $58: x9
sp + $50: x8
sp + $48: x7
sp + $40: x6
sp + $38: x5
sp + $30: x4
sp + $28: x3
sp + $20: x2
sp + $18: x1
sp + $10: x0
sp + $08: nzcv
sp + $00: daif
```

Aarch64 doesn't allow direct access to the PC, so on saving the
context, we save the LR. On load, we branch directly to the saved
address
