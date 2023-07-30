// Branch depending on the current EL
#define SWITCH_EL(reg, el3_label, el2_label, el1_label) \
  mrs reg, CurrentEL;                                   \
  cmp	reg, #0x8;                                      \
  b.gt	el3_label;                                      \
  b.eq	el2_label;                                      \
  b.lt	el1_label;

// Start a function definition, aligned for the architecture
#define ENTRY_ALIGN(name, alignment)            \
  .global name;                                 \
  .type name,%function;                         \
  .align alignment;                             \
name:                                           \
  .cfi_startproc;

// Generic function entry
#define ENTRY(name) ENTRY_ALIGN(name, 6)

// End a function definition
#define END(name)                               \
  .cfi_endproc;                                 \
  .size name, .-name;

// Load a PC-relative address into a register.
#define LDR_REL(register, symbol)               \
  adrp register, symbol;                        \
  add  register, register, #:lo12:##symbol

// Load an absolute address into a register
#define LDR_ABS(register, symbol)               \
  movz register, #:abs_g3:##symbol;             \
  movk register, #:abs_g2_nc:##symbol;          \
  movk register, #:abs_g1_nc:##symbol;          \
  movk register, #:abs_g0_nc:##symbol;

// Generate the optimal set of instructions to load a 64-bit immediate
// value into a register.
.macro  LDR_IMM64 reg,value
    .if \value & 0xffff || (\value == 0)
    movz    \reg,#\value & 0xffff
    .endif
    .if \value > 0xffff && ((\value>>16) & 0xffff) != 0
    .if \value & 0xffff
    movk    \reg,#(\value>>16) & 0xffff,lsl #16
    .else
    movz    \reg,#(\value>>16) & 0xffff,lsl #16
    .endif
    .endif
    .if \value > 0xffffffff && ((\value>>32) & 0xffff) != 0
    .if \value & 0xffffffff
    movk    \reg,#(\value>>32) & 0xffff,lsl #32
    .else
    movz    \reg,#(\value>>32) & 0xffff,lsl #32
    .endif
    .endif
    .if \value > 0xffffffffffff && ((\value>>48) & 0xffff) != 0
    .if \value & 0xffffffffffff
    movk    \reg,#(\value>>48) & 0xffff,lsl #48
    .else
    movz    \reg,#(\value>>48) & 0xffff,lsl #48
    .endif
    .endif
.endm
