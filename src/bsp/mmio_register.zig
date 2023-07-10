// comptime: Create a type describing a register. Use this for
// memory-mapped IO registers.
//
// The returned type allows raw read & write as well as structured.
// Read and Write should be packed structs that describe the
// interpretation of bits as they are read and as they are written.
pub fn Register(comptime Read: type, comptime Write: type) type {
    return struct {
        raw_ptr: *volatile u32,

        const Self = @This();

        pub fn init(address: usize) Self {
            return .{ .raw_ptr = @as(*volatile u32, @ptrFromInt(address)) };
        }

        pub fn read_raw(self: Self) u32 {
            return self.raw_ptr.*;
        }

        pub fn write_raw(self: Self, value: u32) void {
            self.raw_ptr.* = value;
        }

        pub fn read(self: Self) Read {
            return @bitCast(self.raw_ptr.*);
        }

        pub fn write(self: Self, value: Write) void {
            self.raw_ptr.* = @bitCast(value);
        }

        pub fn modify(self: Self, new_value: anytype) void {
            if (Read != Write) {
                @compileError("Can't modify because read and write types for this register aren't the same.");
            }
            var old_value = self.read();
            const info = @typeInfo(@TypeOf(new_value));
            inline for (info.Struct.fields) |field| {
                @field(old_value, field.name) = @field(new_value, field.name);
            }
            self.write(old_value);
        }
    };
}

// comptime: Create a type describing a register.
// A UniformRegister is like a Register except that it always uses the
// same layout for reading and writing.
pub fn UniformRegister(comptime Read: type) type {
    return Register(Read, Read);
}

// Memory barrier for device read
pub fn memory_barrier() void {
    asm volatile ("DSB SY");
}
