pub const barriers = @import("aarch64/barriers.zig");
pub const cache = @import("aarch64/cache.zig");
pub const exceptions = @import("aarch64/exceptions.zig");
pub const mmu = @import("aarch64/mmu.zig");
pub const registers = @import("aarch64/registers.zig");
pub const time = @import("aarch64/time.zig");

// The BSS symbols are provided by the linker script, which computes
// them from the object files produced by the compiler.
pub const Sections = struct {
    pub extern var __bss_start: u8;
    pub extern var __bss_end_exclusive: u8;
    pub extern var __page_tables_start: u8;
};

export fn bssInit() void {
    const bss_start: [*]u8 = @ptrCast(&Sections.__bss_start);
    const bss_end: [*]u8 = @ptrCast(&Sections.__bss_end_exclusive);
    const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

    @memset(bss_start[0..bss_len], 0);
}

/// Note: this performs an "exception return" on the CPU. It will
/// change the stack point and exception level, meaning that this does
/// not return to the call site.
pub inline fn eret() noreturn {
    asm volatile ("eret");
    unreachable;
}

/// Wait for interrupt
pub inline fn wfi() void {
    asm volatile ("wfi");
}

pub const MAX_CORES = 8;

pub const Cpu = struct {
    core_id: u8 = 0,
    int_disable_count: u64 = 0,
    irq_was_disabled: bool = false,
};

pub var cores = [_]Cpu{.{}} ** MAX_CORES;

/// Return core # for the currently executing PE
pub inline fn core_id() u8 {
    return asm (
        \\ mrs %[ret], MPIDR_EL1
        \\ and %[ret], %[ret], 0xff
        : [ret] "=r" (-> u8),
    );
}

pub fn init() void {
    inline for (0..MAX_CORES) |cid| {
        cores[cid] = .{
            .core_id = cid,
            .int_disable_count = 0,
            .irq_was_disabled = false,
        };
    }

    exceptions.init();
}

pub fn coreCurrent() *Cpu {
    return &cores[core_id()];
}

// interruptDisable and interruptEnable act like a stack. We count the
// number of disables and only actually turn interrupts back on when a
// matching number of enables are called.
pub fn interruptDisable() void {
    const cpu = coreCurrent();
    const flags = exceptions.irqFlagsSave();

    // bit 7 of irq_flags is set if interrupts are already disabled
    if (cpu.int_disable_count == 0) {
        if (flags & 0x40 != 0) {
            cpu.irq_was_disabled = true;
        } else {
            exceptions.irqDisable();
        }
    }

    cpu.int_disable_count += 1;
}

pub fn interruptEnable() void {
    const cpu = coreCurrent();

    cpu.int_disable_count -= 1;

    if (cpu.int_disable_count == 0 and !cpu.irq_was_disabled) {
        exceptions.irqEnable();
    }
}
