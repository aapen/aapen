const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;

const bsp = @import("../bsp.zig");
const InterruptController = bsp.common.InterruptController;
const DMAController = bsp.common.DMAController;
const DMAChannel = bsp.common.DMAChannel;
const DMARequest = bsp.common.DMARequest;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

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

    const DebugInforamtion = extern struct {
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
        transfer_information: u32,
        source_address: u32,
        destination_address: u32,
        transfer_length: u32,
        stride: u32,
        next_control_block: u32,
        _reserved_0: u32 = 0,
        _reserved_1: u32 = 0,
    };

    allocator: *Allocator = undefined,
    dma_translations: *AddressTranslations = undefined,
    channel_registers: [*]volatile ChannelRegisters = undefined,
    interrupt_status: *volatile u32 = undefined,
    transfer_enabled: *volatile u32 = undefined,
    intc: *InterruptController = undefined,
    in_use: [16]bool = [_]bool{false} ** 16,

    pub fn init(self: *BroadcomDMAController, allocator: *Allocator, base: u64, interrupt_controller: *InterruptController, dma_translations: *AddressTranslations) void {
        self.allocator = allocator;
        self.dma_translations = dma_translations;
        self.channel_registers = @ptrFromInt(base);
        self.interrupt_status = @ptrFromInt(base + 0xfe0);
        self.transfer_enabled = @ptrFromInt(base + 0xff0);
        self.intc = interrupt_controller;
    }

    pub fn dma(self: *BroadcomDMAController) bsp.common.DMAController {
        return bsp.common.DMAController.init(self);
    }

    // TODO: after dma completes, free the control block
    pub fn initiate(self: *BroadcomDMAController, channel: DMAChannel, request: *DMARequest) bsp.common.DMAError!void {
        const control_block = try self.allocator.create(BroadcomDMAControlBlock);
        const which_registers = channel.context;

        self.awaitCompletionSpin(which_registers);

        control_block.transfer_information = 0;
        control_block.source_address = @truncate(toChild(self.dma_translations, request.source));
        control_block.destination_address = @truncate(toChild(self.dma_translations, request.destination));
        control_block.transfer_length = @truncate(request.length);
        control_block.stride = @truncate(request.stride);
        control_block.next_control_block = 0;

        self.channel_registers[which_registers].control_block_addr = @truncate(toChild(self.dma_translations, @intFromPtr(control_block)));
        // self.channel_registers[which_registers].control_block_addr = @truncate(@intFromPtr(control_block));

        self.channel_registers[which_registers].control.active = 1;

        const control = self.channel_registers[which_registers].control;
        kprint("dma src: {x:0>8}\tdst: {x:0>8}\tlen: {x:0>8}\tstride: {x:0>8}\n", .{ control_block.source_address, control_block.destination_address, control_block.transfer_length, control_block.stride });
        kprint("dma status: active = {}\tend = {}\terror = {}\n", .{ control.active, control.end, control.dma_error });
    }

    inline fn dmaBusy(self: *BroadcomDMAController, channel: usize) bool {
        return self.channel_registers[channel].control.active == 0x1;
    }

    fn awaitCompletionSpin(self: *BroadcomDMAController, channel: usize) void {
        while (self.dmaBusy(channel)) {}
    }

    pub fn reserveChannel(self: *BroadcomDMAController) !DMAChannel {
        for (self.in_use, 0..) |b, i| {
            if (!b) {
                self.in_use[i] = true;
                return DMAChannel{ .context = i };
            }
        }
        return bsp.common.DMAError.NoAvailableChannel;
    }

    pub fn releaseChannel(self: *BroadcomDMAController, channel: DMAChannel) void {
        const idx = channel.context;
        self.in_use[idx] = false;
    }

    pub fn channelWaitClear(self: *BroadcomDMAController, channel: DMAChannel) void {
        const control = self.channel_registers[channel.context].control;
        kprint("dma status: active = {}\tend = {}\terror = {}\n", .{ control.active, control.end, control.dma_error });

        self.awaitCompletionSpin(channel.context);
    }
};
