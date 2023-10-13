const std = @import("std");
const Allocator = std.mem.Allocator;

const hal = @import("../hal.zig");
const InterruptController = hal.interfaces.InterruptController;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

extern fn spinDelay(cpu_cycles: u32) void;

pub const BroadcomDMAController = struct {
    const ControlAndStatus = packed struct {
        active: u1 = 0,
        end: u1 = 0,
        interrupt_status: u1 = 0,
        data_request: u1 = 0,
        paused: u1 = 0,
        data_request_stops_dma: u1 = 0,
        waiting_for_outstanding_writes: u1 = 0,
        _reserved_0: u1 = 0,
        dma_error: u1 = 0,
        _reserved_1: u7 = 0,
        priority: u4 = 0,
        panic_priority: u4 = 0,
        _reserved_2: u4 = 0,
        wait_for_outstanding_writes: u1 = 0,
        disable_debug: u1 = 0,
        abort: u1 = 0,
        reset: u1 = 0,
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
        read_last_not_set_error: u1 = 0,
        fifo_error: u1 = 0,
        read_error: u1 = 0,
        _reserved_0: u1 = 0,
        outstanding_writes: u4 = 0,
        dma_id: u8 = 0,
        dma_state: u9 = 0,
        version: u3 = 0,
        lite: u1 = 0,
        _reserved_1: u3 = 0,
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

    const ChannelId = u5;

    const max_channel_id: ChannelId = 14;

    const ChannelContext = struct {
        id: ChannelId,
        registers: *volatile ChannelRegisters,
    };

    interface: hal.interfaces.DMAController = undefined,
    allocator: *Allocator = undefined,
    register_base: u64 = undefined,
    dma_translations: *AddressTranslations = undefined,
    interrupt_status: *volatile u32 = undefined,
    transfer_enabled: *volatile u32 = undefined,
    intc: *InterruptController = undefined,
    in_use: [max_channel_id]bool = [_]bool{false} ** max_channel_id,

    pub fn init(self: *BroadcomDMAController, allocator: *Allocator, base: u64, interrupt_controller: *InterruptController, dma_translations: *AddressTranslations) void {
        self.interface = .{
            .reserveChannel = reserveChannel,
            .initiate = initiate,
            .awaitChannel = awaitChannel,
            .releaseChannel = releaseChannel,
        };

        self.allocator = allocator;
        self.dma_translations = dma_translations;
        self.register_base = base;
        self.interrupt_status = @ptrFromInt(base + 0xfe0);
        self.transfer_enabled = @ptrFromInt(base + 0xff0);
        self.intc = interrupt_controller;
    }

    pub fn dma(self: *BroadcomDMAController) *hal.interfaces.DMAController {
        return &self.interface;
    }

    fn channelClaimUnused(self: *BroadcomDMAController) !ChannelId {
        for (self.in_use, 0..max_channel_id) |b, i| {
            if (!b) {
                self.in_use[i] = true;
                return @as(ChannelId, @intCast(i));
            }
        }
        return hal.interfaces.DMAError.NoAvailableChannel;
    }

    fn channelRegisters(self: *BroadcomDMAController, channel_id: ChannelId) *volatile ChannelRegisters {
        return @ptrFromInt(self.register_base + (0x100 * @as(usize, channel_id)));
    }

    fn reserveChannel(intf: *hal.interfaces.DMAController) hal.interfaces.DMAError!hal.interfaces.DMAChannel {
        const self = @fieldParentPtr(@This(), "interface", intf);

        var channel_id = try self.channelClaimUnused();
        var context = try self.allocator.create(ChannelContext);
        var channel_registers = self.channelRegisters(channel_id);

        context.* = ChannelContext{
            .id = channel_id,
            .registers = channel_registers,
        };

        self.transfer_enabled.* = @as(u32, 1) << channel_id;

        spinDelay(3);

        // we assert the reset flag, the DMA controller deasserts it
        // when reset completes
        channel_registers.control.reset = 1;
        while (channel_registers.control.reset == 1) {}

        return hal.interfaces.DMAChannel{ .context = context };
    }

    // TODO: after dma completes, free the control block
    pub fn initiate(intf: *hal.interfaces.DMAController, channel: hal.interfaces.DMAChannel, request: *hal.interfaces.DMARequest) hal.interfaces.DMAError!void {
        const self = @fieldParentPtr(@This(), "interface", intf);

        const control_block = try self.allocator.create(BroadcomDMAControlBlock);
        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        var channel_registers = context.registers;

        const mode_2d: u1 = if (request.stride != 0) 1 else 0;

        control_block.transfer_information = TransferInformation{
            .source_width = 1,
            .source_increment = 1,
            .destination_width = 1,
            .destination_increment = 1,
            .two_d_mode = mode_2d,
        };

        control_block.source_address = @truncate(toChild(self.dma_translations, request.source));
        control_block.destination_address = @truncate(toChild(self.dma_translations, request.destination));
        control_block.transfer_length = @truncate(request.length);
        control_block.stride = @truncate(request.stride);
        control_block.next_control_block = 0;

        channel_registers.control_block_addr = @truncate(toChild(self.dma_translations, @intFromPtr(control_block)));
        channel_registers.control = ControlAndStatus{
            .active = 1,
            .priority = 1,
            .panic_priority = 15,
            .wait_for_outstanding_writes = 0,
        };
    }

    /// blocks until DMA completes. returns true on success, false if
    /// an error happened
    fn awaitChannel(intf: *hal.interfaces.DMAController, channel: hal.interfaces.DMAChannel) bool {
        const self = @fieldParentPtr(@This(), "interface", intf);
        _ = self;

        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        const channel_registers = context.registers;

        while (channel_registers.control.active == 0b1) {}

        return channel_registers.control.dma_error == 0;
    }

    fn releaseChannel(intf: *hal.interfaces.DMAController, channel: hal.interfaces.DMAChannel) void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        self.in_use[context.id] = false;
    }
};
