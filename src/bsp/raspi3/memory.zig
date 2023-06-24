/// Actual memory layout of a Raspberry Pi 3

// The architecture-independent types
const memory = @import("../../memory.zig");
const TD = memory.TranslationDescriptor;

// These symbols are provided by the linker
const __code_start: *u64 = @extern(*u64, .{ .name = "__code_start" });
const __code_end_exclusive: *u64 = @extern(*u64, .{ .name = "__code_end_exclusive" });

const layout = [_]TD{
    TD.create(@ptrToInt(__code_start), @ptrToInt(__code_end) - 1, 0x00000000, .ReadWrite, .CacheableDRAM, false, "Kernel code and read-only data"),
    TD.create(0x1fff0000, 0x1fffffff, 0x201F0000, .ReadWrite, .Device, true, "Remapped copy of MMIO registers"),
    TD.create(0x3f000000, 0x4000ffff, 0x00000000, .ReadWrite, .Device, true, "Identity-mapped location of MMIO registers"),
};
