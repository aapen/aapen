const bcm_mailbox = @import("bcm_mailbox.zig");
const BroadcomMailbox = bcm_mailbox.BroadcomMailbox;
const Message = BroadcomMailbox.Message;
const Envelope = BroadcomMailbox.Envelope;

const common = @import("../bsp/common.zig");
const BoardInfo = common.BoardInfo;
const BoardInfoController = common.BoardInfoController;

const memory = @import("../memory.zig");
const Regions = memory.Regions;
const Region = memory.Region;

pub const BroadcomBoardInfoController = struct {
    arm_memory_range: Region = Region{ .name = "ARM Memory" },
    videocore_memory_range: Region = Region{ .name = "Videocore Memory" },

    mailbox: *BroadcomMailbox = undefined,

    pub fn init(self: *BroadcomBoardInfoController, mailbox: *BroadcomMailbox) void {
        self.mailbox = mailbox;
    }

    pub fn controller(self: *BroadcomBoardInfoController) BoardInfoController {
        return common.BoardInfoController.init(self);
    }

    pub fn inspect(self: *BroadcomBoardInfoController, info: *BoardInfo) void {
        var arm_memory = GetMemoryRange.arm();
        var vc_memory = GetMemoryRange.videocore();
        var revision = GetInfo.boardRevision();
        var mac_address = GetInfo.macAddress();
        var serial = GetInfo.serialNumber();
        var messages = [_]Message{
            arm_memory.message(),
            vc_memory.message(),
            revision.message(),
            mac_address.message(),
            serial.message(),
        };
        var env = Envelope.init(self.mailbox, &messages);
        _ = env.call() catch 0;

        arm_memory.copy(&self.arm_memory_range);
        vc_memory.copy(&self.videocore_memory_range);

        info.memory.regions.append(self.arm_memory_range) catch {};
        info.memory.regions.append(self.videocore_memory_range) catch {};

        info.device.mac_address = mac_address.value;
        info.device.serial_number = serial.value;

        self.decode_revision(revision.value, info);
    }

    fn decode_revision(self: *BroadcomBoardInfoController, revision: u32, info: *BoardInfo) void {
        if (revision & 0x800000 == 0x800000) {
            self.decode_revision_new_scheme(revision, info);
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

    fn decode_revision_new_scheme(_: *BroadcomBoardInfoController, revision: u32, info: *BoardInfo) void {
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
};

const GetInfo = struct {
    const Self = @This();

    tag: BroadcomMailbox.RpiFirmwarePropertyTag = undefined,
    value: u32 = undefined,

    pub fn boardRevision() Self {
        return Self{ .tag = .rpi_firmware_get_board_revision };
    }

    pub fn macAddress() Self {
        return Self{ .tag = .rpi_firmware_get_board_mac_address };
    }

    pub fn serialNumber() Self {
        return Self{ .tag = .rpi_firmware_get_board_serial };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, self.tag, 0, 1);
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

    tag: BroadcomMailbox.RpiFirmwarePropertyTag = undefined,
    memory_base: u32 = undefined,
    memory_size: u32 = undefined,

    pub fn arm() Self {
        return Self{ .tag = .rpi_firmware_get_arm_memory };
    }

    pub fn videocore() Self {
        return Self{ .tag = .rpi_firmware_get_vc_memory };
    }

    pub fn message(self: *Self) Message {
        return Message.init(self, self.tag, 0, 2);
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
