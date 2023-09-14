const std = @import("std");
const root = @import("root");

const devicetree = @import("../devicetree.zig");
const Node = devicetree.Fdt.Node;

pub const Error = error{
    NotIdentified,
    NotSupported,
};

const SupportedBoard = enum {
    RaspberryPi_3,
    RaspberryPi_3b,
    RaspberryPi_3b_plus,
    RaspberryPi_4,
    RaspberryPi_4b,
    RaspberryPi_400,
};

const CompatString = struct { []const u8, SupportedBoard };

const compat_strings = [_]CompatString{
    .{ "raspberrypi,3", .RaspberryPi_3 },
    .{ "raspberrypi,3-model-b", .RaspberryPi_3b },
    .{ "raspberrypi,3-model-b-plus", .RaspberryPi_3b_plus },
    .{ "raspberrypi,4", .RaspberryPi_4 },
    .{ "raspberrypi,4-model-b", .RaspberryPi_4b },
    .{ "raspberrypi,400", .RaspberryPi_400 },
};

pub fn identify(root_node: *Node) !SupportedBoard {
    if (root_node.property("compatible")) |prop| {
        const compatible: []const u8 = prop.valueAsString();

        const brk = std.mem.indexOfScalar(u8, compatible, 0) orelse compatible.len;

        root.kprint("searching for {s}\n", .{compatible[0..brk]});

        inline for (compat_strings) |c| {
            if (std.mem.eql(u8, c[0], compatible[0..brk])) {
                return c[1];
            }
        }
    } else {
        return Error.NotIdentified;
    }

    return Error.NotSupported;
}

pub fn detectAndInit(root_node: *Node) !void {
    const board = try identify(root_node);

    switch (board) {
        .RaspberryPi_3,
        .RaspberryPi_3b,
        .RaspberryPi_3b_plus,
        => {
            const raspi3 = @import("raspi3.zig");
            try raspi3.init();
        },
        .RaspberryPi_4,
        .RaspberryPi_4b,
        .RaspberryPi_400,
        => {
            return Error.NotSupported;
        },
    }
}
