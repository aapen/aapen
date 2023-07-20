const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;
const Region = @import("../../../mem.zig").Region;

pub const BoardInfo = struct {
    model_str: []u8 = undefined,
    model: u32 = undefined,
    revision_str: []u8 = undefined,
    revision: u32 = undefined,
    mac_address: u32 = undefined,
    arm_memory: Region = undefined,
    videocore_memory: Region = undefined,

    pub fn read(self: *BoardInfo) !void {
        var arm_memory = GetMemory.arm();
        var vc_memory = GetMemory.videocore();
        var messages = [_]mailbox.Message{
            arm_memory.message(),
            vc_memory.message(),
        };
        var env = mailbox.Envelope.init(&messages);
        _ = try env.call();
        self.arm_memory = arm_memory.region();
        self.videocore_memory = vc_memory.region();
    }
};

const GetMemory = struct {
    const Self = @This();

    tag: mailbox.rpi_firmware_property_tag = undefined,
    name: []const u8 = undefined,
    memory_base: u32 = undefined,
    memory_size: u32 = undefined,

    pub fn arm() Self {
        return Self{ .name = "ARM Memory", .tag = .RPI_FIRMWARE_GET_ARM_MEMORY };
    }

    pub fn videocore() Self {
        return Self{ .name = "Videocore Memory", .tag = .RPI_FIRMWARE_GET_VC_MEMORY };
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, self.tag, 0, 2, fill, unfill);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        _ = self;
        _ = buf;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.memory_base = buf[0];
        self.memory_size = buf[1];
    }

    pub fn region(self: *Self) Region {
        var r = Region.fromSize(self.memory_base, self.memory_size);
        r.name = self.name;
        return r;
    }
};
