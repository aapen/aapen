const root = @import("root");

const Rectangle = @import("rectangle.zig").Rectangle;

const spin: [8]u8 = [_]u8{ '|', '/', '-', '\\', '|', '/', '-', '\\' };
var spindex: u8 = 0;

pub fn heartbeat(_: *anyopaque) void {
    const cb = root.char_buffer;
    const rows = cb.num_rows;
    const cols = cb.num_cols;

    while (true) {
        spindex = (spindex + 1) & 0x7;
        cb.charSet(cols - 1, rows - 1, spin[spindex]);
        cb.syncText();
        root.schedule.sleep(500) catch {};
    }
}
