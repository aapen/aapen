/// Actual memory layout of a Raspberry Pi 3

// The architecture-independent types
const memory = @import("../../memory.zig");
const TD = memory.TranslationDescriptor;

// These symbols are provided by the linker
const __code_start: *u64 = @extern(*u64, .{ .name = "__code_start" });
const __code_end_exclusive: *u64 = @extern(*u64, .{ .name = "__code_end_exclusive" });

pub const address_space = memory.AddressSpace(0xFFFF_FFFF);

const mmio_start = 0x3f00_0000;
const mmio_end_excl = 0x4001_0000;
const gpio_offset = 0x0020_0000;
const uart_offset = 0x0020_1000;

pub const MMIO = .{
    .start = mmio_start,
    .end_inclusive = mmio_end_excl - 1,
    .gpio_start = mmio_start + gpio_offset,
    .pl011_uart_start = mmio_start + uart_offset,
};

pub const layout = memory.KernelVirtualLayout{
    .max_virtual_address_inclusive = address_space.max_address(),
    .descriptors = [_]TD{
        TD.create(
            @ptrToInt(__code_start),
            @ptrToInt(__code_end_exclusive),
            0x00000000,
            .ReadWrite,
            .CacheableDRAM,
            false,
            "Kernel code and read-only data",
        ),
        TD.create(
            0x1fff0000,
            0x1fffffff,
            0x201F0000,
            .ReadWrite,
            .Device,
            true,
            "Remapped copy of MMIO registers",
        ),
        TD.create(
            mmio_start,
            mmio_end_excl,
            0x00000000,
            .ReadWrite,
            .Device,
            true,
            "Identity-mapped location of MMIO registers",
        ),
    },
};
