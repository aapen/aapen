const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const InterruptController = root.HAL.InterruptController;

const Forth = @import("../forty/forth.zig").Forth;

const architecture = @import("../architecture.zig");
const barriers = architecture.barriers;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const synchronize = @import("../synchronize.zig");
const AllocationSet = synchronize.AllocationSet;

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    _ = forth;
}

extern fn spinDelay(cpu_cycles: u32) void;

pub const Channel = struct {
    channel_id: u8,
    registers: *volatile ChannelRegisters,
};

pub const DMAError = error{
    NoAvailableChannel,
    OutOfMemory,
};

const BroadcomDMAControlBlock = extern struct {
    transfer_information: TransferInformation,
    source_address: u32,
    destination_address: u32,
    transfer_length: u32,
    stride: u32,
    next_control_block: u32,
    _reserved_0: u32 = 0,
    _reserved_1: u32 = 0,
};

pub const Request = struct {
    control_blocks: ?[]BroadcomDMAControlBlock = null,
    source: u32 = 0,
    source_increment: bool = true,
    destination: u32 = 0,
    destination_increment: bool = true,
    length: usize = 0,
    stride: usize = 0,
};

const ControlAndStatus = packed struct {
    active: u1 = 0, // 0
    end: u1 = 0, // 1
    interrupt_status: u1 = 0, // 2
    data_request: u1 = 0, // 3

    paused: u1 = 0, // 4
    data_request_stops_dma: u1 = 0, // 5
    waiting_for_outstanding_writes: u1 = 0, // 6
    _reserved_0: u1 = 0, // 7

    dma_error: u1 = 0, // 8
    _reserved_1: u7 = 0, // 9..15

    priority: u4 = 0, // 16..19

    panic_priority: u4 = 0, // 20..23

    _reserved_2: u4 = 0, // 24..27

    wait_for_outstanding_writes: u1 = 0, // 28
    disable_debug: u1 = 0, // 29
    abort: u1 = 0, // 30
    reset: u1 = 0, // 31
};

const TransferInformation = packed struct {
    interrupt_enable: u1 = 0,
    two_d_mode: u1 = 0,
    _reserved_0: u1 = 0,
    wait_for_response: u1 = 0,
    destination_increment: u1 = 0,
    destination_width: u1 = 0,
    destination_data_request: u1 = 0,
    destination_ignore: u1 = 0,
    source_increment: u1 = 0,
    source_width: u1 = 0,
    source_data_request: u1 = 0,
    source_ignore: u1 = 0,
    burst_length: u4 = 0,
    peripheral_mapping: u5 = 0,
    wait_cycles: u5 = 0,
    no_wide_bursts: u1 = 0,
    _reserved_1: u5 = 0,
};

const DebugInformation = extern struct {
    read_last_not_set_error: u1 = 0, // 0
    fifo_error: u1 = 0, // 1
    read_error: u1 = 0, // 2
    _reserved_0: u1 = 0, // 3
    outstanding_writes: u4 = 0, // 4..7
    dma_id: u8 = 0, // 8..15
    dma_state: u9 = 0, // 16..24
    version: u3 = 0, // 25..27
    lite: u1 = 0, // 28
    _reserved_1: u3 = 0, // 29..31
};

const ChannelRegisters = extern struct {
    control: ControlAndStatus,
    control_block_addr: u32,
    transfer_information: TransferInformation,
    source_address: u32,
    destination_address: u32,
    transfer_length: u32,
    stride: u32,
    next_control_block_addr: u32,
    debug: u32,
};

const ChannelId = u5;

const max_channel_id: ChannelId = 14;
const DmaChannels = AllocationSet("bcm_dma channels", u5, max_channel_id);

//    clock: *Clock = undefined,
allocator: Allocator,
register_base: u64,
translations: *const AddressTranslations,
interrupt_status: *volatile u32,
transfer_enabled: *volatile u32,
intc: *InterruptController,
channels: DmaChannels,
channel_control_blocks: [max_channel_id]BroadcomDMAControlBlock align(32),

pub fn init(
    allocator: Allocator,
    register_base: u64,
    intc: *InterruptController,
    translations: *AddressTranslations,
) Self {
    return .{
        .allocator = allocator,
        .register_base = register_base,
        .intc = intc,
        .interrupt_status = @ptrFromInt(register_base + 0xfe0),
        .transfer_enabled = @ptrFromInt(register_base + 0xff0),
        .translations = translations,
        .channels = .{},
        .channel_control_blocks = undefined,
    };
}

fn channelClaimUnused(self: *Self) !ChannelId {
    const id = self.channels.allocate() catch {
        return DMAError.NoAvailableChannel;
    };
    return @as(ChannelId, @intCast(id));
}

fn channelRegisters(self: *Self, channel_id: ChannelId) *volatile ChannelRegisters {
    return @ptrFromInt(self.register_base + (0x100 * @as(usize, channel_id)));
}

pub fn reserveChannel(self: *Self) DMAError!Channel {
    const channel_id = try self.channelClaimUnused();
    var channel_registers = self.channelRegisters(channel_id);

    self.transfer_enabled.* = @as(u32, 1) << channel_id;

    spinDelay(3);

    // we assert the reset flag, the DMA controller deasserts it
    // when reset completes
    channel_registers.control.reset = 1;
    while (channel_registers.control.reset == 1) {}

    return .{
        .channel_id = channel_id,
        .registers = channel_registers,
    };
}

pub fn initiate(self: *Self, channel: Channel, request: *Request) DMAError!void {
    const channel_registers = channel.registers;
    const control_block = &self.channel_control_blocks[channel.channel_id];
    const mode_2d: u1 = if (request.stride != 0) 1 else 0;

    control_block.* = .{
        .transfer_information = TransferInformation{
            .source_width = 1,
            .source_increment = if (request.source_increment) 1 else 0,
            .destination_width = 1,
            .destination_increment = if (request.destination_increment) 1 else 0,
            .two_d_mode = mode_2d,
        },

        .source_address = @truncate(toChild(self.translations, request.source)),
        .destination_address = @truncate(toChild(self.translations, request.destination)),
        .transfer_length = @truncate(request.length),
        .stride = @truncate(request.stride),
        .next_control_block = 0,
        ._reserved_0 = 0,
        ._reserved_1 = 0,
    };

    // Make sure everything the CPU has touched is visible to the DMA
    // controller
    barriers.barrierMemoryWrite();
    synchronize.dataCacheRangeClean(@intFromPtr(control_block), @sizeOf(BroadcomDMAControlBlock));
    synchronize.dataCacheRangeClean(request.source, request.length);

    const control_block_bus_addr: u32 = @truncate(toChild(self.translations, @intFromPtr(control_block)));
    channel_registers.control_block_addr = control_block_bus_addr;
    channel_registers.control = ControlAndStatus{
        .active = 1,
        .priority = 1,
        .panic_priority = 15,
        .wait_for_outstanding_writes = 0,
    };
}

/// blocks until DMA completes. returns true on success, false if
/// an error happened
pub fn awaitChannel(self: *Self, channel: Channel) bool {
    _ = self;

    // apply a timeout. for now this is a fixed delay of about 200 ms,
    // but it will need to be a parameter in the future.
    //
    // also this will overflow and panic if we ever run for 2^64
    // ticks and try to do a dma
    //
    // would be nice to have a general 'watchdog' facility that we
    // could apply to any word
    const start_time = root.hal.clock.ticks();
    const deadline = start_time + 200_000;

    const channel_registers = channel.registers;

    var current_time = start_time;
    while (channel_registers.control.active == 0b1) : (current_time = root.hal.clock.ticks()) {
        if (current_time >= deadline) {
            root.debug.kernelMessage("dma timeout");
            if (channel_registers.control.dma_error != 0) {
                root.debug.kernelMessage("dma error");
            }
            return false;
        }
    }

    return channel_registers.control.dma_error == 0;
}

pub fn releaseChannel(self: *Self, channel: Channel) void {
    self.transfer_enabled.* &= ~(@as(u32, 1) << channel.channel_id);
    self.channels.free(channel.channel_id);
}
