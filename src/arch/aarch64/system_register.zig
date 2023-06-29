// ARMv8-A uses negative logic on some trap enable bits
pub const TrapEnableBitN = enum(u1) {
    trap_disable = 1,
    trap_enable = 0,
};

// ARMv8-A uses positive logic on some trap enable bits
pub const TrapEnableBitP = enum(u1) {
    trap_disable = 0,
    trap_enable = 1,
};

/// comptime: Create a type describing an AArch64 system register (CPU
/// register). Use this for registers accessed with `mrs` and `msr` instructions.
///
/// The returned type allows raw read & write as well as structured.
/// Read and Write should be packed structs that describe the
/// interpretation of bits as they are read and as they are written.
///
/// Credit to jamie@scatteredthoughts.net for this approach:
/// https://www.scattered-thoughts.net/writing/mmio-in-zig/
pub fn SystemRegister(comptime name: []const u8, comptime Read: type, comptime Write: type) type {
    return struct {
        pub fn read_raw() u64 {
            return asm ("mrs %[ret], " ++ name
                : [ret] "={X0}" (-> u64),
                :
                : "X0"
            );
        }

        pub fn write_raw(value: u64) void {
            asm volatile ("msr " ++ name ++ ", %[val]"
                :
                : [val] "{X0}" (value),
                : "X0"
            );
        }

        pub fn read() Read {
            return @bitCast(read_raw());
        }

        pub fn write(value: Write) void {
            write_raw(@bitCast(value));
        }

        pub fn modify(new_value: anytype) void {
            if (Read != Write) {
                @compileError("Can't modify because read and write types for this register aren't the same.");
            }
            var old_value = read();
            const info = @typeInfo(@TypeOf(new_value));
            inline for (info.Struct.fields) |field| {
                @field(old_value, field.name) = @field(new_value, field.name);
            }
            write(old_value);
        }
    };
}

// comptime: Create a type describing a system register.
// A UniformSystemRegister is like a SystemRegister except that it always uses the
// same layout for reading and writing.
pub fn UniformSystemRegister(comptime name: []const u8, comptime Read: type) type {
    return SystemRegister(name, Read, Read);
}
