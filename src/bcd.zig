const std = @import("std");

pub fn decode(comptime T: type, val: T) !T {
    var ret: T = 0;
    const nibbles = @bitSizeOf(T) / 4;
    inline for (0..nibbles) |i| {
        const nibble = (val >> (4 * i)) & 0xf;
        if (nibble > 0b1001) {
            return error.Overflow;
        }

        ret += (nibble * std.math.pow(T, 10, i));
    }
    return ret;
}
