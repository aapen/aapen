const mailbox = @import("../mailbox.zig");
const Message = mailbox.Message;
const Envelope = mailbox.Envelope;
const Region = @import("../../../memory.zig").Region;

pub const Model = struct {
    name: []const u8 = undefined,
    version: ?u8 = null,
    processor: []const u8 = undefined,
    memory: ?u32 = null,
    pcb_revision: ?u32 = null,
};

pub const Device = struct {
    manufacturer: []const u8 = undefined,
    serial_number: ?u32 = null,
    mac_address: ?u32 = null,
};

pub const BoardInfo = struct {
    model: Model = Model{},
    device: Device = Device{},
    memory_size: u32 = 0,
    arm_memory_range: Region = Region{ .name = "ARM Memory" },
    videocore_memory_range: Region = Region{ .name = "Videocore Memory" },

    pub fn read(self: *BoardInfo) !void {
        var arm_memory = GetMemoryRange.arm();
        var vc_memory = GetMemoryRange.videocore();
        var revision = GetInfo.boardRevision();
        var mac_address = GetInfo.macAddress();
        var serial = GetInfo.serialNumber();
        var messages = [_]mailbox.Message{
            arm_memory.message(),
            vc_memory.message(),
            revision.message(),
            mac_address.message(),
            serial.message(),
        };
        var env = mailbox.Envelope.init(&messages);
        _ = env.call() catch 0;

        arm_memory.copy(&self.arm_memory_range);
        vc_memory.copy(&self.videocore_memory_range);

        self.device.mac_address = mac_address.value;
        self.device.serial_number = serial.value;
        self.decode_revision(revision.value);
    }

    fn decode_revision(self: *BoardInfo, revision: u32) void {
        if (revision & 0x800000 == 0x800000) {
            self.decode_revision_new_scheme(revision);
        } else {}
    }

    const processor_names = [_][]const u8{ "Broadcom 2835", "Broadcom 2836", "Broadcom 2837", "Broadcom 2711" };
    const manufacturer_names = [_][]const u8{ "Sony", "Egoman", "Embest", "Sony Japan", "Embest", "Stadium" };
    const memory_sizes = [_]u16{ 256, 512, 1024, 2048, 4096, 8192 };

    const BoardType = struct { name: []const u8, version: ?u8 };

    const board_types = [_]BoardType{
        BoardType{ .name = "Model A", .version = 1 },
        BoardType{ .name = "Model B", .version = 1 },
        BoardType{ .name = "Model A+", .version = 1 },
        BoardType{ .name = "Model B+", .version = 1 },
        BoardType{ .name = "Model 2B", .version = 2 },
        BoardType{ .name = "Alpha", .version = null },
        BoardType{ .name = "Compute Module 1", .version = null },
        BoardType{ .name = "Unknown", .version = null },
        BoardType{ .name = "Model 3B", .version = 3 },
        BoardType{ .name = "Model Zero", .version = 0 },
        BoardType{ .name = "Compute Module 3", .version = 3 },
        BoardType{ .name = "Unknown", .version = null },
        BoardType{ .name = "Zero W", .version = 0 },
        BoardType{ .name = "Model 3B+", .version = 3 },
        BoardType{ .name = "Model 3A+", .version = 3 },
        BoardType{ .name = "Internal", .version = null },
        BoardType{ .name = "Compute Module 3+", .version = 3 },
        BoardType{ .name = "Model 4B", .version = 4 },
    };

    fn decode_revision_new_scheme(self: *BoardInfo, revision: u32) void {
        // var warranty: u2 = (revision >> 24) & 0b11;
        var memory: u32 = (revision >> 20) & 0b111;
        var manufacturer: u32 = (revision >> 16) & 0b1111;
        var processor: u32 = (revision >> 12) & 0b1111;
        var board: u32 = (revision >> 4) & 0b11111111;
        var pcb_revision: u32 = revision & 0b1111;

        self.model = Model{
            .name = if (board < board_types.len) board_types[board].name else "Unknown",
            .version = if (board < board_types.len) board_types[board].version else null,
            .pcb_revision = pcb_revision,
            .memory = if (memory < memory_sizes.len) memory_sizes[memory] else 0,
            .processor = if (processor < processor_names.len) processor_names[processor] else "Unknown",
        };
        self.device.manufacturer = if (manufacturer < manufacturer_names.len) manufacturer_names[manufacturer] else "Unknown";
    }
};

const GetInfo = struct {
    const Self = @This();

    tag: mailbox.RpiFirmwarePropertyTag = undefined,
    value: u32 = undefined,

    pub fn boardRevision() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_BOARD_REVISION };
    }

    pub fn macAddress() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_BOARD_MAC_ADDRESS };
    }

    pub fn serialNumber() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_BOARD_SERIAL };
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, self.tag, 0, 1);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        _ = self;
        _ = buf;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.value = buf[0];
    }
};

const GetMemoryRange = struct {
    const Self = @This();

    tag: mailbox.RpiFirmwarePropertyTag = undefined,
    memory_base: u32 = undefined,
    memory_size: u32 = undefined,

    pub fn arm() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_ARM_MEMORY };
    }

    pub fn videocore() Self {
        return Self{ .tag = .RPI_FIRMWARE_GET_VC_MEMORY };
    }

    pub fn message(self: *Self) mailbox.Message {
        return mailbox.Message.init(self, self.tag, 0, 2);
    }

    pub fn fill(self: *Self, buf: []u32) void {
        _ = self;
        _ = buf;
    }

    pub fn unfill(self: *Self, buf: []u32) void {
        self.memory_base = buf[0];
        self.memory_size = buf[1];
    }

    pub fn copy(self: *Self, target: *Region) void {
        target.fromSize(self.memory_base, self.memory_size);
    }
};
