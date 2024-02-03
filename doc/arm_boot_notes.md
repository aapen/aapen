# Aarch64 boot code

Researching multicore boot. As documented elsewhere, core 0 starts
executing user code at 0x80000. Cores 1 - 3 park waiting for a
"wakeup" signal. This happens in two parts:

- Each core goes into `wfe`.
- If awakened, the core loads a vector from a fixed address plus an
  offset times the core number: `0xd8 + core_id * 8`
- If the vector is zero, the core loops back to the `wfe`
- If non-zero, the core jumps to the specified address.

## Strategy

1. Boot core initializes itself, prepares for `eret` to EL1
2. Boot core writes 0x80000 to $e0, does a `dsb sy` followed by `sev`. This wakes up core 1.
3. Boot core writes same vector to $e8 and $f0, with a `sev` after each. This wakes up cores 2 and 3.
4. Our boot code at 0x80000 must be safe for all cores:
   5. It must skip the `bssInit` call on non-boot cores.
   6. It must compute a different stack pointer for each core.

## Stub code used by Qemu

In Qemu, core 1 - 3 loop at vector 0x300

```
 0x300   mov     x5, #0xd8                       // #216
 0x304   mrs     x6, mpidr_el1
 0x308   and     x6, x6, #0x3                    // core number in x6
 0x30c   wfe                                                                                             
 0x310   ldr     x4, [x5, x6, lsl #3]            // d8 + (core_id * 8)
 0x314   cbz     x4, 0x30c                       // if zero, go back to sleep
 0x318   mov     x0, #0x0 
 0x31c   mov     x1, #0x0 
 0x320   mov     x2, #0x0 
 0x324   mov     x3, #0x0 
 0x328   br      x4                              // use value at $d8 + (core_id * 8) as vector
```

## Stub code on RPi 3

Stub code on the RPi is a little different but has the same effect.

```
 0x68    mrs     x6, mpidr_el1                   //
 0x6c    and     x6, x6, #0x3                    // core number in x6
 0x70    cbz     x6, 0x8c                        // on boot core, jump to 0x8c
 0x74    adr     x5, 0xd8                        // compute address 0xd8 -> x5
 0x78    wfe                                     // 
 0x7c    ldr     x4, [x5, x6, lsl #3]            // d8 + (core_id * 8)
 0x80    cbz     x4, 0x78                        // if zero, go back to sleep
 0x84    mov     x0, #0x0                        // 
 0x88    b       0x94                            // jump to 0x94
 0x8c    ldr     w4, 0xfc                        // get boot vector from 0xfc. at boot is 0x80000
 0x90    ldr     w0, 0xf8                        // magic number 0xd00dfeed
 0x94    mov     x1, #0x0            
 0x98    mov     x2, #0x0            
 0x9c    mov     x3, #0x0            
 0xa0    br      x4                              // jump to boot
```
