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
#define LDR_IMM64(register, value)                              \
  #if value & 0xffff || (value == 0)                            \
    movz    register,#value & 0xffff                            \
    #endif                                                      \
    #if value &  > 0xffff && ((value>>16) & 0xffff) != 0        \
    #if value & 0xffff                                          \
    movk   register,#(value>>16) & 0xffff,lsl #16               \
    #else                                                       \
    movz   register,#(value>>16) & 0xffff,lsl #16               \
    #endif                                                      \
    #endif                                                      \
    #if (value > 0xffffffff && ((value>>32) & 0xffff) != 0)     \
    #if (value & 0xffffffff)                                    \
    movk    register,#(value>>32) & 0xffff,lsl #32              \
    #else                                                       \
    movz    register,#(value>>32) & 0xffff,lsl #32              \
    #endif                                                      \
    #endif                                                      \
    #if (value > 0xffffffffffff && ((value>>48) & 0xffff) != 0) \
    #if (value & 0xffffffffffff)                                \
    movk    register,#(value>>48) & 0xffff,lsl #48              \
    #else                                                       \
    movz    register,#(value>>48) & 0xffff,lsl #48              \
    #endif                                                      \
    #endif
