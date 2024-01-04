const root = @import("root");

const Rectangle = @import("rectangle.zig").Rectangle;

pub fn heartbeat() !void {
    var ch = root.char_buffer.charGet(0, 0);
    if (ch >= 65) {
        ch = ((ch - 64) % 26) + 65;
    } else {
        ch = 65;
    }
    root.char_buffer.charSet(0, 0, ch);
    root.char_buffer.renderRect(Rectangle.init(0, 1, 0, 1));

    root.schedule.sleep(500);
}
