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
    root.char_buffer.syncText();
    root.schedule.sleep(500);
}

// pub fn heartbeat2() !void {
//     const now = root.hal.clock.ticks();

//     if (now < 1_000_000) {
//         root.schedule.sleep(1000);
//         return;
//     }

//     spindex = (spindex + 1) & 0x7;
//     root.char_buffer.charSet(1, 0, spin[spindex]);
//     root.char_buffer.syncText();
//     root.schedule.sleep(2500);
// }

// const spin: []const u8 = "|/-\\|/-\\";
// var spindex: u8 = 0;
