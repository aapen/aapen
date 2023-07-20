const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;

pub const BoardInfo = struct {
    model_str: []u8 = undefined,
    model: u32 = undefined,
    revision_str: []u8 = undefined,
    revision: u32 = undefined,
    mac_address: u32 = undefined,
    arm_memory_base: u32 = undefined,
    arm_memory_size: u32 = undefined,
    videocore_memory_base: u32 = undefined,
    videocore_memory_size: u32 = undefined,

    pub fn read(self: *BoardInfo) !void {
        var arm_memory = GetMemory.arm();
        var vc_memory = GetMemory.videocore();
        var messages = [_]mailbox.Message{
            arm_memory.message(),
            vc_memory.message(),
        };
        var env = mailbox.Envelope.init(&messages);
        _ = try env.call();
        self.arm_memory_base = arm_memory.memory_base;
        self.arm_memory_size = arm_memory.memory_size;
        self.videocore_memory_base = vc_memory.memory_base;
        self.videocore_memory_size = vc_memory.memory_size;
    }
};

const GetMemory = struct {
    const Self = @This();

    tag: mailbox.rpi_firmware_property_tag = undefined,
    memory_base: u32 = undefined,
    memory_size: u32 = undefined,

    pub fn arm() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_ARM_MEMORY };
    }

    pub fn videocore() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_VC_MEMORY };
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
};
