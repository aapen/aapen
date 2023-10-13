/// VTable for a common serial interface
pub const Serial = struct {
    getc: *const fn (serial: *Serial) u8,
    putc: *const fn (serial: *Serial, ch: u8) void,
    puts: *const fn (serial: *Serial, buffer: []const u8) usize,
    hasc: *const fn (serial: *Serial) bool,
};
