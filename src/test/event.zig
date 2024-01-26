const std = @import("std");

const helpers = @import("helpers.zig");
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const event = @import("../event.zig");
const Event = event.Event;
const EventType = event.EventType;
const EventSubtype = event.EventSubtype;

pub fn testBody() !void {
    assertEventSize();
    assertEventTypePosition();
}

fn assertEventSize() void {
    expectEqual(64, @bitSizeOf(Event));
}

fn assertEventTypePosition() void {
    const ev: Event = .{};
    expectEqual(0, ev.type);

    const ev2: Event = .{ .type = EventType.Key, .subtype = EventSubtype.Key.Pressed };
    expectEqual(2, ev2.type);
    expectEqual(1, ev2.subtype);

    var evbytes = std.mem.asBytes(&ev2);
    expectEqual(@as(u8, 2), evbytes[0]);
    expectEqual(@as(u8, 1), evbytes[1]);
}
