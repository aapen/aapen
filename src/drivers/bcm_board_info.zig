const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const Mailbox = root.HAL.Mailbox;
const PropertyTag = root.HAL.Mailbox.PropertyTag;

const memory = @import("../memory.zig");

const Self = @This();

pub const BoardInfo = struct {
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

    pub const Memory = struct {
        regions: memory.Regions = undefined,
    };

    model: Model = Model{},
    device: Device = Device{},
    memory: Memory = Memory{},

    pub fn init(self: *BoardInfo, allocator: Allocator) void {
        self.memory.regions = memory.Regions.init(allocator);
    }
};

mailbox: *Mailbox,

pub fn init(mailbox: *Mailbox) Self {
    return .{
        .mailbox = mailbox,
    };
}

pub fn inspect(self: *Self, info: *BoardInfo) !void {
    var board_info = PropertyBoardInfo.init();
    try self.mailbox.getTags(&board_info, @sizeOf(PropertyBoardInfo) / 4);

    try info.memory.regions.append(memory.Region.fromSize("ARM memory", board_info.arm_memory.base, board_info.arm_memory.size));
    try info.memory.regions.append(memory.Region.fromSize("VC memory", board_info.vc_memory.base, board_info.vc_memory.size));

    info.device.mac_address = board_info.mac_address.value;
    info.device.serial_number = board_info.serial.value;

    decode_revision(board_info.revision.value, info);
}

fn decode_revision(revision: u32, info: *BoardInfo) void {
    if (revision & 0x800000 == 0x800000) {
        decode_revision_new_scheme(revision, info);
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

fn decode_revision_new_scheme(revision: u32, info: *BoardInfo) void {
    // var warranty: u2 = (revision >> 24) & 0b11;
    var memsize: u32 = (revision >> 20) & 0b111;
    var manufacturer: u32 = (revision >> 16) & 0b1111;
    var processor: u32 = (revision >> 12) & 0b1111;
    var board: u32 = (revision >> 4) & 0b11111111;
    var pcb_revision: u32 = revision & 0b1111;

    info.model = BoardInfo.Model{
        .name = if (board < board_types.len) board_types[board].name else "Unknown",
        .version = if (board < board_types.len) board_types[board].version else null,
        .pcb_revision = pcb_revision,
        .memory = if (memsize < memory_sizes.len) memory_sizes[memsize] else 0,
        .processor = if (processor < processor_names.len) processor_names[processor] else "Unknown",
    };
    info.device.manufacturer = if (manufacturer < manufacturer_names.len) manufacturer_names[manufacturer] else "Unknown";
}

const PropertyBoardInfo = extern struct {
    arm_memory: PropertyMemory = .{ .tag = PropertyTag.init(.rpi_firmware_get_arm_memory, 0, 2) },
    vc_memory: PropertyMemory = .{ .tag = PropertyTag.init(.rpi_firmware_get_vc_memory, 0, 2) },
    revision: PropertyInfo = .{ .tag = PropertyTag.init(.rpi_firmware_get_board_revision, 1, 1) },
    mac_address: PropertyInfo = .{ .tag = PropertyTag.init(.rpi_firmware_get_board_mac_address, 1, 1) },
    serial: PropertyInfo = .{ .tag = PropertyTag.init(.rpi_firmware_get_board_serial, 1, 1) },

    pub fn init() PropertyBoardInfo {
        return .{};
    }
};

const PropertyInfo = extern struct {
    tag: PropertyTag,
    value: u32 = 0,
};

const PropertyMemory = extern struct {
    tag: PropertyTag,
    base: u32 = 0,
    size: u32 = 0,
};
