const root = @import("root");
const kwarn = root.kwarn;

const std = @import("std");
const Allocator = std.mem.Allocator;

const hal2 = @import("../hal2.zig");

const hal = @import("../hal.zig");
//const Clock = hal.interfaces.Clock;
const DMAChannel = hal.interfaces.DMAChannel;
const DMAController = hal.interfaces.DMAController;
const DMAError = hal.interfaces.DMAError;
const DMARequest = hal.interfaces.DMARequest;
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

    const BroadcomDMARequest = struct {
        control_blocks: ?[]BroadcomDMAControlBlock,
        request: DMARequest,
    };

    const ChannelId = u5;

    const max_channel_id: ChannelId = 14;

    const ChannelContext = struct {
        id: ChannelId,
        registers: *volatile ChannelRegisters,
    };

    interface: DMAController = undefined,
    //    clock: *Clock = undefined,
    allocator: *Allocator = undefined,
    register_base: u64 = undefined,
    dma_translations: *AddressTranslations = undefined,
    interrupt_status: *volatile u32 = undefined,
    transfer_enabled: *volatile u32 = undefined,
    intc: *InterruptController = undefined,
    in_use: [max_channel_id]bool = [_]bool{false} ** max_channel_id,

    pub fn init(self: *BroadcomDMAController, allocator: *Allocator, base: u64, interrupt_controller: *InterruptController, dma_translations: *AddressTranslations) void {
        self.interface = .{
            .createRequest = createRequest,
            .destroyRequest = destroyRequest,
            .reserveChannel = reserveChannel,
            .initiate = initiate,
            .awaitChannel = awaitChannel,
            .releaseChannel = releaseChannel,
        };

        self.allocator = allocator;
        self.dma_translations = dma_translations;
        //        self.clock = clock;
        self.register_base = base;
        self.interrupt_status = @ptrFromInt(base + 0xfe0);
        self.transfer_enabled = @ptrFromInt(base + 0xff0);
        self.intc = interrupt_controller;
    }

    pub fn dma(self: *BroadcomDMAController) *DMAController {
        return &self.interface;
    }

    fn channelClaimUnused(self: *BroadcomDMAController) !ChannelId {
        for (self.in_use, 0..max_channel_id) |b, i| {
            if (!b) {
                self.in_use[i] = true;
                return @as(ChannelId, @intCast(i));
            }
        }
        return DMAError.NoAvailableChannel;
    }

    fn channelRegisters(self: *BroadcomDMAController, channel_id: ChannelId) *volatile ChannelRegisters {
        return @ptrFromInt(self.register_base + (0x100 * @as(usize, channel_id)));
    }

    fn reserveChannel(intf: *DMAController) DMAError!DMAChannel {
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

        return DMAChannel{ .owner = intf, .context = context };
    }

    fn createRequest(intf: *DMAController) DMAError!*DMARequest {
        const self = @fieldParentPtr(@This(), "interface", intf);

        var request = try self.allocator.create(BroadcomDMARequest);
        request.control_blocks = null;
        return &request.request;
    }

    fn destroyRequest(intf: *DMAController, request: *DMARequest) void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const request_owner = @fieldParentPtr(BroadcomDMARequest, "request", request);

        if (request_owner.control_blocks) |cb_slice| {
            self.allocator.free(cb_slice);
        }

        self.allocator.destroy(request_owner);
    }

    // TODO: after dma completes, free the control block
    pub fn initiate(intf: *DMAController, channel: DMAChannel, request: *DMARequest) DMAError!void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const request_owner = @fieldParentPtr(BroadcomDMARequest, "request", request);

        const cb_slice = try self.allocator.alignedAlloc(BroadcomDMAControlBlock, 32, 1);
        const control_block = &cb_slice[0];
        request_owner.control_blocks = cb_slice;

        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        var channel_registers = context.registers;

        // kwarn(@src(), "Zig believes the control block alignment to be {d}\n", .{@alignOf(BroadcomDMAControlBlock)});
        // kwarn(@src(), "Control block allocated at 0x{x:0>8} in ARM memory\n", .{@intFromPtr(control_block)});

        const mode_2d: u1 = if (request.stride != 0) 1 else 0;

        control_block.* = .{
            .transfer_information = TransferInformation{
                .source_width = 1,
                .source_increment = if (request.source_increment) 1 else 0,
                .destination_width = 1,
                .destination_increment = if (request.destination_increment) 1 else 0,
                .two_d_mode = mode_2d,
            },

            .source_address = @truncate(toChild(self.dma_translations, request.source)),
            .destination_address = @truncate(toChild(self.dma_translations, request.destination)),
            .transfer_length = @truncate(request.length),
            .stride = @truncate(request.stride),
            .next_control_block = 0,
            ._reserved_0 = 0,
            ._reserved_1 = 0,
        };

        const control_block_bus_addr: u32 = @truncate(toChild(self.dma_translations, @intFromPtr(control_block)));
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
    fn awaitChannel(intf: *DMAController, channel: DMAChannel) bool {
        const self = @fieldParentPtr(@This(), "interface", intf);
        _ = self;

        // apply a timeout. for now this is a fixed delay, but it will
        // need to be a parameter in the future.
        //
        // also this will overflow and panic if we ever run for 2^64
        // ticks and try to do a dma
        //
        // would be nice to have a general 'watchdog' facility that we
        // could apply to any word
        const start_time = hal2.clock.ticks();
        const deadline = start_time + 1_500_000;

        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        const channel_registers = context.registers;

        var current_time = start_time;
        while (channel_registers.control.active == 0b1) : (current_time = hal2.clock.ticks()) {
            if (current_time >= deadline) {
                kwarn(@src(), "DMA on channel {} exceeded timeout by {d}\n", .{ context.id, (current_time - deadline) });
                return false;
            }
        }

        return channel_registers.control.dma_error == 0;
    }

    fn releaseChannel(intf: *DMAController, channel: DMAChannel) void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const context: *ChannelContext = @ptrCast(@alignCast(channel.context));
        self.in_use[context.id] = false;
    }
};
