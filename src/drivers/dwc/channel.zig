const reg = @import("registers.zig");
pub const ChannelCharacteristics = reg.ChannelCharacteristics;
pub const ChannelSplitControl = reg.ChannelSplitControl;
pub const ChannelInterrupt = reg.ChannelInterrupt;
pub const DwcTransferSizePid = reg.DwcTransferSizePid;
pub const TransferSize = reg.TransferSize;
pub const ChannelRegisters = reg.ChannelRegisters;

pub const ChannelId = u5;

const Self = @This();

id: ChannelId = 0,
registers: *volatile reg.ChannelRegisters = undefined,
busy: bool = false,

pub fn init(self: *Self, id: ChannelId, channel_register_base: u64) void {
    self.* = .{
        .id = id,
        .registers = @ptrFromInt(channel_register_base + (@sizeOf(ChannelRegisters) * @as(usize, id))),
        .busy = false,
    };
}
