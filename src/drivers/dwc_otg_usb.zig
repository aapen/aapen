const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;
const InterruptController = root.HAL.InterruptController;
const IrqId = InterruptController.IrqId;
const IrqHandlerFn = InterruptController.IrqHandlerFn;
const IrqHandler = InterruptController.IrqHandler;

const local_timer = @import("arm_local_timer.zig");
const Clock = local_timer.Clock;

const PowerController = root.HAL.PowerController;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const memory_map = root.HAL.memory_map;

const synchronize = @import("../synchronize.zig");
const Spinlock = synchronize.Spinlock;

const ChannelSet = @import("../channel_set.zig");

const reg = @import("dwc/registers.zig");

const usb = @import("../usb.zig");

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

const dwc_max_channels = 16;
const dwc_wait_blocks = dwc_max_channels;
const ChannelId = u5;

const Self = @This();

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

pub const Error = error{
    IncorrectDevice,
    PowerFailure,
    ConfigurationError,
    OvercurrentDetected,
    InvalidResponse,
    NoChannelAvailable,
};

// ----------------------------------------------------------------------
// Channel Registers
// ----------------------------------------------------------------------
pub const ChannelCharacteristics = reg.ChannelCharacteristics;
pub const ChannelSplitControl = reg.ChannelSplitControl;
pub const ChannelInterrupt = reg.ChannelInterrupt;
pub const DwcTransferSizePid = reg.DwcTransferSizePid;
pub const TransferSize = reg.TransferSize;
pub const ChannelRegisters = reg.ChannelRegisters;

// ----------------------------------------------------------------------
// Host Registers
// ----------------------------------------------------------------------
pub const HostConfig = reg.HostConfig;
pub const HostFrameInterval = reg.HostFrameInterval;
pub const HostFrames = reg.HostFrames;
pub const HostPeriodicFifo = reg.HostPeriodicFifo;
pub const HostPort = reg.HostPort;
pub const HostRegisters = reg.HostRegisters;

// ----------------------------------------------------------------------
// Core Registers
// ----------------------------------------------------------------------
pub const OtgControl = reg.OtgControl;
pub const AhbConfig = reg.AhbConfig;
pub const UsbConfig = reg.UsbConfig;
pub const Reset = reg.Reset;
pub const InterruptStatus = reg.InterruptStatus;
pub const InterruptMask = reg.InterruptMask;
pub const RxStatus = reg.RxStatus;
pub const NonPeriodicTxFifoSize = reg.NonPeriodicTxFifoSize;
pub const NonPeriodicTxFifoStatus = reg.NonPeriodicTxFifoStatus;
pub const GeneralCoreConfig = reg.GeneralCoreConfig;
pub const HwConfig2 = reg.HwConfig2;
pub const HwConfig3 = reg.HwConfig3;
pub const HwConfig4 = reg.HwConfig4;
pub const PeriodicTxFifoSize = reg.PeriodicTxFifoSize;
pub const CoreRegisters = reg.CoreRegisters;

pub const VTable = struct {
    initialize: *const fn (usb_controller: u64) u64,
    initializeRootPort: *const fn (usb_controller: u64) u64,
    dumpStatus: *const fn (usb_controller: u64) void,
};

allocator: Allocator,
core_registers: *volatile CoreRegisters,
host_registers: *volatile HostRegisters,
channel_registers: *volatile [dwc_max_channels]ChannelRegisters,
power_and_clock_control: *volatile u32,
all_channel_intmask_lock: Spinlock,
intc: *InterruptController,
irq_id: IrqId,
irq_handler: IrqHandler = .{
    .callback = irqHandle,
},
translations: *const AddressTranslations,
power_controller: *PowerController,
clock: *Clock,
root_port: RootPort,
num_host_channels: u4,
channels: ChannelSet,
stage_data: [dwc_max_channels]*TransferStageData,
wait_block_allocations: ChannelSet,
wait_blocks: [dwc_wait_blocks]bool,
vtable: VTable = .{
    .initialize = initializeShim,
    .initializeRootPort = initializeRootPortShim,
    .dumpStatus = dumpStatusInteropShim,
},

fn initializeShim(usb_controller: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);
    if (self.initialize()) {
        return 1;
    } else |err| {
        std.log.err("USB init error: {any}", .{err});
        return 0;
    }
}

fn initializeRootPortShim(usb_controller: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);
    if (self.initializeRootPort()) {
        return 1;
    } else |err| {
        std.log.err("USB init root port error: {any}", .{err});
        return 0;
    }
}

fn dumpStatusInteropShim(usb_controller: u64) void {
    var self: *Self = @ptrFromInt(usb_controller);
    self.dumpStatus();
}

pub fn init(
    allocator: Allocator,
    register_base: u64,
    intc: *InterruptController,
    irq_id: IrqId,
    translations: *AddressTranslations,
    power: *PowerController,
    clock: *Clock,
) Self {
    return .{
        .allocator = allocator,
        .core_registers = @ptrFromInt(register_base),
        .host_registers = @ptrFromInt(register_base + 0x400),
        .channel_registers = @ptrFromInt(register_base + 0x500),
        .power_and_clock_control = @ptrFromInt(register_base + 0xe00),
        .all_channel_intmask_lock = Spinlock.init("all channels interrupt mask", true),
        .intc = intc,
        .irq_id = irq_id,
        .translations = translations,
        .power_controller = power,
        .clock = clock,
        .root_port = RootPort.init(allocator),
        .num_host_channels = 0,
        .channels = ChannelSet.init("DWC OTG Host controller channels", dwc_max_channels),
        .wait_block_allocations = ChannelSet.init("Wait blocks", dwc_wait_blocks),
        .wait_blocks = [_]bool{false} ** dwc_wait_blocks,
        .stage_data = undefined,
    };
}

pub fn initialize(self: *Self) !void {
    try self.powerOn();
    try self.verifyHostControllerDevice();
    try self.disableGlobalInterrupts();
    try self.connectInterruptHandler();
    try self.initializeControllerCore();
    try self.enableCommonInterrupts();
    try self.enableGlobalInterrupts();
    try self.initializeHost();
    // NOTE: I'm extracting this to a separate step which will build a
    // device on a port
    //    try self.initializeRootPort();
}

fn powerOn(self: *Self) !void {
    const power_result = try self.power_controller.powerOn(.usb_hcd);

    if (power_result != .power_on) {
        std.log.err("Failed to power on USB device: {any}\n", .{power_result});
        return Error.PowerFailure;
    }
}

fn powerOff(self: *Self) !void {
    const power_result = try self.power_controller.powerOff(.usb_hcd);

    if (power_result != .power_off) {
        std.log.err("Failed to power off USB device: {any}\n", .{power_result});
        return Error.PowerFailure;
    }
}

fn verifyHostControllerDevice(self: *Self) !void {
    const id = self.core_registers.vendor_id;

    kprint("   DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

    if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
        std.log.warn(" gsnpsid = {x:0>8}\nvendor = {x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
        return Error.IncorrectDevice;
    }
}

fn disableGlobalInterrupts(self: *Self) !void {
    self.core_registers.ahb_config.global_interrupt_mask = 0;
}

fn enableGlobalInterrupts(self: *Self) !void {
    self.core_registers.ahb_config.global_interrupt_mask = 1;
}

fn connectInterruptHandler(self: *Self) !void {
    self.intc.connect(self.irq_id, &self.irq_handler);
    self.intc.enable(self.irq_id);
}

fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    var self = @fieldParentPtr(Self, "irq_handler", this);

    const intr_status = self.core_registers.core_interrupt_status;

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel_intr == 1) {
        const all_intrs = self.host_registers.all_channel_interrupts;
        self.host_registers.all_channel_interrupts = all_intrs;

        // Find the channel that has something to say
        var channel_mask: u32 = 1;
        // TODO consider using @ctz to find the lowest bit that's set,
        // instead of looping over all 16 channels.
        for (0..dwc_max_channels) |channel| {
            if ((all_intrs & channel_mask) != 0) {
                // Mask the channel's interrupt, then call the
                // channel-specific handler
                self.channel_registers[channel].channel_int_mask = @bitCast(@as(u32, 0));
                self.irqHandleChannel(@truncate(channel));
            }
            channel_mask <<= 1;
        }
    }

    // clear the interrupt bits
    self.core_registers.core_interrupt_status = intr_status;
}

fn irqHandleChannel(self: *Self, which_channel: u5) void {
    std.log.debug("channel intr on {d}", .{which_channel});

    var stage = self.stage_data[which_channel];

    if (stage == undefined) {
        std.log.debug("spurious interrupt", .{});
        return;
    }

    std.log.debug("ch {d} interrupt status {x:0>8}", .{ which_channel, @as(u32, @bitCast(self.channel_registers[which_channel].channel_int)) });

    var request = stage.request;

    switch (stage.substate) {
        .not_set => {
            std.log.debug("Unexpected interrupt", .{});
        },
        .wait_for_channel_disable => {
            std.log.info("channel {d}, was waiting for disable to finish", .{which_channel});
            self.channelStart(stage);
            return;
        },
        .wait_for_transaction_complete => {
            // TODO clean and invalidate dcache for packet range
            const transfer_size = self.channel_registers[which_channel].channel_transfer_size;
            const channel_intr = self.channel_registers[which_channel].channel_int;

            std.log.info("channel {d}, waiting for transaction complete, intr {x:0>8}", .{ which_channel, @as(u32, @bitCast(channel_intr)) });
            // should check for done transaction here... remaining
            // transfer zero, and complete bit set
            //
            // ... without that, this infinitely restarts the
            // transaction
            //

            // // restart halted transaction
            // if (channel_intr.halted == 1) {
            //     // TODO should this enqueue the transaction for later?
            //     // self.transactionStart(stage) catch {
            //     //     root.debug.kernelMessage("Error starting txn");
            //     //     // TODO clean up, this transaction will never finish
            //     // };
            //     return;
            // }

            stage.transactionComplete(
                which_channel,
                channel_intr,
                transfer_size.transfer_size_packets,
                transfer_size.transfer_size_bytes,
            );
            //            return;
        },
    }

    switch (stage.state) {
        .not_set => {
            std.log.warn("unexpected state", .{});
        },
        .no_split_transfer => {
            std.log.debug("status stage (i think?)", .{});

            var status: ChannelInterrupt = stage.transaction_status;

            // TOOD handle nak / nyet status with periodic transaction
            if (status.isStatusError()) {
                std.log.err("usb txn failed (status 0x{x:0>8})", .{@as(u32, @bitCast(status))});
            } else {
                std.log.debug("maybe request is complete", .{});

                if (stage.status_stage) {
                    std.log.debug("status stage returned {d} bytes", .{stage.resultLength()});
                    request.result_length = stage.resultLength();
                }
                request.status = 1;
            }

            self.channelInterruptDisable(which_channel);
            self.allocator.destroy(stage);
            self.stage_data[which_channel] = undefined;
            self.channelFree(which_channel);

            // TODO call completion routine on the request.
        },
        // TODO case for start split, case for finish split
    }
}

fn initializeControllerCore(self: *Self) !void {
    // clear bits 20 & 22 of core usb config register
    var config: UsbConfig = self.core_registers.usb_config;
    config.ulpi_ext_vbus_drv = 0;
    config.term_sel_dl_pulse = 0;
    self.core_registers.usb_config = config;

    try self.resetControllerCore();

    config.ulpi_utmi_sel = 0;
    config.phy_if = 0;
    self.core_registers.usb_config = config;

    const hw2 = self.core_registers.hardware_config_2;
    config = self.core_registers.usb_config;
    if (hw2.hs_phy_type == .ulpi and hw2.fs_phy_type == .dedicated) {
        config.ulpi_fsls = 1;
        config.ulpi_clk_sus_m = 1;
    } else {
        config.ulpi_fsls = 0;
        config.ulpi_clk_sus_m = 0;
    }
    self.core_registers.usb_config = config;

    self.num_host_channels = hw2.num_host_channels;

    var ahb = self.core_registers.ahb_config;
    ahb.dma_enable = 1;
    ahb.wait_axi_writes = 1;
    ahb.max_axi_burst = 0;
    self.core_registers.ahb_config = ahb;

    config = self.core_registers.usb_config;
    config.hnp_capable = 0;
    config.srp_capable = 0;
    self.core_registers.usb_config = config;
}

fn enableCommonInterrupts(self: *Self) !void {
    self.core_registers.core_interrupt_status = @bitCast(@as(u32, 0xffff_ffff));
}

fn resetControllerCore(self: *Self) !void {
    // wait up to 100 ms for reset to settle
    const end = self.deadline(100);

    // TODO what should we do if we don't see the idle signal
    while (self.clock.ticks() < end and self.core_registers.reset.ahb_idle != 1) {}

    self.core_registers.reset.soft_reset = 1;

    // wait up to 10 ms for reset to finish
    const reset_end = self.deadline(10);
    // TODO what should we do if we don't see the soft_reset go to zero?
    while (self.clock.ticks() < reset_end and self.core_registers.reset.soft_reset != 0) {}

    // wait 100 ms
    const wait_end = self.deadline(100);
    while (self.clock.ticks() < wait_end) {}
}

fn initializeHost(self: *Self) !void {
    std.log.info("host init start", .{});

    self.power_and_clock_control.* = 0;

    var config = self.host_registers.config;

    if (self.core_registers.hardware_config_2.hs_phy_type == .ulpi and
        self.core_registers.hardware_config_2.fs_phy_type == .dedicated and
        self.core_registers.usb_config.ulpi_fsls == 1)
    {
        config.fsls_pclk_sel = .sel_48_mhz;
    } else {
        config.fsls_pclk_sel = .sel_30_60_mhz;
    }
    self.host_registers.config = config;

    try self.flushTxFifo();
    self.delayMicros(1);

    try self.flushRxFifo();
    self.delayMicros(1);

    try self.powerHostPort();
    try self.enableHostInterrupts();

    std.log.info("host init end", .{});
}

fn configPhyClockSpeed(self: *Self) !void {
    const core_config = self.core_registers.usb_config;
    const hw2 = self.core_registers.hardware_config_2;
    if (hw2.hs_phy_type == .ulpi and hw2.fs_phy_type == .dedicated and core_config.ulpi_fsls) {
        self.host_registers.config.fsls_pclk_sel = .sel_48_mhz;
    } else {
        self.host_registers.config.fsls_pclk_sel = .sel_30_60_mhz;
    }
}

fn flushTxFifo(self: *Self) !void {
    const FLUSH_ALL_TX_FIFOS = 0x10;

    var reset = self.core_registers.reset;
    reset.tx_fifo_flush = 1;
    reset.tx_fifo_flush_num = FLUSH_ALL_TX_FIFOS;
    self.core_registers.reset = reset;

    const reset_end = self.deadline(10);
    while (self.clock.ticks() < reset_end and self.core_registers.reset.tx_fifo_flush != 0) {}
}

fn flushRxFifo(self: *Self) !void {
    self.core_registers.reset.rx_fifo_flush = 1;
    const reset_end = self.deadline(10);
    while (self.clock.ticks() < reset_end and self.core_registers.reset.rx_fifo_flush != 0) {}
}

fn powerHostPort(self: *Self) !void {
    if (self.host_registers.port.power == 0) {
        self.host_registers.port.power = 1;
    }
}

fn enableHostInterrupts(self: *Self) !void {
    var int_mask: InterruptMask = @bitCast(@as(u32, 0));
    int_mask.host_channel_intr = 1;
    self.core_registers.core_interrupt_mask = int_mask;

    // clear all pending interrupts
    self.core_registers.core_interrupt_status = @bitCast(@as(u32, 0xffffffff));
}

fn initializeRootPort(self: *Self) !void {
    std.log.info("root port init start", .{});
    try self.root_port.initialize(self);
    std.log.info("root port init end", .{});
}

pub fn getPortSpeed(self: *Self) !usb.UsbSpeed {
    return switch (self.host_registers.port.speed) {
        .high => .High,
        .full => .Full,
        .low => .Low,
        else => Error.ConfigurationError,
    };
}

// TODO migrate this to the clock
fn deadline(self: *Self, millis: u32) u64 {
    const start_ticks = self.clock.ticks();
    const elapsed_ticks = millis * 1_000; // clock freq is 1Mhz
    return start_ticks + elapsed_ticks;
}

fn delayMillis(self: *Self, count: u32) void {
    self.delayMicros(count * 1000);
}

// TODO migrate this to the clock
fn delayMicros(self: *Self, count: u32) void {
    const start_ticks = self.clock.ticks();
    const elapsed_ticks = count; // clock freq is 1Mhz
    const end_ticks = start_ticks + elapsed_ticks;
    while (self.clock.ticks() <= end_ticks) {}
}

pub fn dumpStatus(self: *Self) void {
    kprint("{s: >28}\n", .{"Core registers"});
    dumpRegister("otg_control", @bitCast(self.core_registers.otg_control));
    dumpRegister("ahb_config", @bitCast(self.core_registers.ahb_config));
    dumpRegister("usb_config", @bitCast(self.core_registers.usb_config));
    dumpRegister("reset", @bitCast(self.core_registers.reset));
    dumpRegister("interrupt_status", @bitCast(self.core_registers.core_interrupt_status));
    dumpRegister("interrupt_mask", @bitCast(self.core_registers.core_interrupt_mask));
    dumpRegister("rx_fifo_size", @bitCast(self.core_registers.rx_fifo_size));
    dumpRegister("nonperiodic_tx_fifo_size", @bitCast(self.core_registers.nonperiodic_tx_fifo_size));
    dumpRegister("nonperiodic_tx_status", @bitCast(self.core_registers.nonperiodic_tx_status));

    kprint("{s: >28}\n", .{""});
    kprint("{s: >28}\n", .{"Host registers"});
    dumpRegister("config", @bitCast(self.host_registers.config));
    dumpRegister("frame_interval", @bitCast(self.host_registers.frame_interval));
    dumpRegister("frame_num", @bitCast(self.host_registers.frame_num));
    dumpRegister("periodic_tx_fifo_status", @bitCast(self.host_registers.periodic_tx_fifo_status));
    dumpRegister("all_channel_interrupts", @bitCast(self.host_registers.all_channel_interrupts));
    dumpRegister("all_channel_interrupts_mask", @bitCast(self.host_registers.all_channel_interrupts_mask));
    dumpRegister("frame_list_base_addr", @bitCast(self.host_registers.frame_list_base_addr));
    dumpRegister("port", @bitCast(self.host_registers.port));
}

fn dumpRegister(field_name: []const u8, v: u32) void {
    kprint("{s: >28}: {x:0>8}\n", .{ field_name, v });
}

fn controlMessage(
    self: *Self,
    endpoint: *Endpoint,
    request_type: usb.RequestType,
    request: u8,
    value: u16,
    index: u16,
    data: *align(DMA_ALIGNMENT) anyopaque,
    data_size: u16,
) !u19 {
    const raw_setup_data: []align(DMA_ALIGNMENT) u8 = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(SetupPacket));
    const setup: *align(DMA_ALIGNMENT) SetupPacket = @ptrCast(@alignCast(raw_setup_data));

    setup.* = .{
        .request_type = @bitCast(request_type),
        .request = request,
        .value = value,
        .index = index,
        .length = data_size,
    };
    const rq = try Request.init(self.allocator, endpoint, data, data_size, setup);

    try self.requestSubmitBlocking(rq);

    return rq.result_length;
}

fn channelAllocate(self: *Self) !ChannelId {
    const chan = try self.channels.allocate();
    errdefer self.channels.free(chan);

    if (chan >= self.num_host_channels) {
        return Error.NoChannelAvailable;
    }
    return chan;
}

fn channelFree(self: *Self, channel: ChannelId) void {
    self.channels.free(channel);
}

const TransferStageState = enum(u8) {
    not_set = 0,
    no_split_transfer = 1,
};

const TransferStageSubstate = enum(u8) {
    not_set = 0,
    wait_for_channel_disable = 1,
    wait_for_transaction_complete = 2,
};

const TransferStageData = struct {
    owner: *Self,
    channel: ChannelId,
    endpoint: *Endpoint,
    request: *Request,
    device: *Device,
    in: bool,
    status_stage: bool,
    speed: usb.UsbSpeed,
    max_packet_size: u11,
    transfer_size: u16,
    bytes_per_transaction: u19,
    packets: u10,
    packets_per_transaction: u10,
    interrupt_mask: u32,
    temp_buffer: []u32,
    buffer_pointer: [*]u8,
    wait_block_assigned: u5,

    state: TransferStageState = .not_set,
    substate: TransferStageSubstate = .not_set,

    total_bytes_transferred: u19 = 0,
    status_mask: ChannelInterrupt,
    transaction_status: ChannelInterrupt,

    fn transferBytesRemaining(self: *TransferStageData) u19 {
        return self.bytes_per_transaction;
    }

    fn transferPacketsRemaining(self: *TransferStageData) u10 {
        return self.packets_per_transaction;
    }

    fn addressDMA(self: *TransferStageData) [*]u8 {
        return self.buffer_pointer;
    }

    fn addressDevice(self: *TransferStageData) u8 {
        return self.device.address;
    }

    fn endpointType(self: *TransferStageData) usb.EndpointType {
        return self.endpoint.type;
    }

    fn endpointNumber(self: *TransferStageData) u4 {
        return self.endpoint.number;
    }

    fn controllerPid(self: *TransferStageData) !DwcTransferSizePid {
        return switch (self.endpoint.pidNext(self.status_stage)) {
            .Setup => .Setup,
            .Data0 => .Data0,
            .Data1 => .Data1,
        };
    }

    fn resultLength(self: *TransferStageData) u19 {
        return @min(self.total_bytes_transferred, self.transfer_size);
    }

    fn transactionComplete(self: *TransferStageData, which_channel: u5, status: ChannelInterrupt, packets_left: u10, bytes_left: u19) void {
        _ = bytes_left;
        _ = packets_left;
        self.transaction_status = status;

        // TODO check for NAK/NYET, see if the request should complete
        // when NAK/NYET. (Should only happen for Bulk endpoints)

        // var packets_transferred: u10 = self.packets_per_transaction - packets_left;
        // var bytes_transferred: u19 = self.bytes_per_transaction - bytes_left;

        // self.total_bytes_transferred += bytes_transferred;
        // self.buffer_pointer += bytes_transferred;

        // // TODO this only happens if a) it's not a split transaction
        // // or b) it _is_ a split and this is the last transaction in
        // // the split
        // self.endpoint.pidSkip(packets_transferred, self.status_stage);

        // self.packets -= packets_transferred;

        // if (self.transfer_size - self.total_bytes_transferred < self.bytes_per_transaction) {
        //     self.bytes_per_transaction = self.transfer_size - self.total_bytes_transferred;
        // }

        self.owner.wait_blocks[self.wait_block_assigned] = false;
        self.owner.wait_block_allocations.free(self.wait_block_assigned);
        self.owner.channelStop(which_channel);
        self.owner.channelFree(which_channel);

        std.log.info("channel {d} transfer complete, signalled waitblock {d}", .{ which_channel, self.wait_block_assigned });
    }
};

fn createStageData(self: *Self, channel: ChannelId, request: *Request, in: bool, status_stage: bool, wait_block_assigned: u5) !*TransferStageData {
    const packet_size = request.endpoint.max_packet_size;

    const stage = try self.allocator.create(TransferStageData);
    stage.owner = self;
    stage.channel = channel;
    stage.request = request;
    stage.endpoint = request.endpoint;
    stage.device = request.endpoint.device;
    stage.wait_block_assigned = wait_block_assigned;
    stage.in = in;
    stage.status_stage = status_stage;
    stage.max_packet_size = packet_size;
    stage.speed = stage.device.speed;
    stage.status_mask = ChannelInterrupt{
        .transfer_completed = 1,
        .halted = 1,
        .ahb_error = 1,
        .stall_response_received = 1,
        .transaction_error = 1,
        .babble_error = 1,
        .frame_overrun = 1,
        .data_toggle_error = 1,
    };

    if (!status_stage) {
        if (request.endpoint.pidNext(status_stage) == .Setup) {
            stage.buffer_pointer = @ptrCast(request.setup_data);
            stage.transfer_size = @sizeOf(SetupPacket);
        } else {
            stage.buffer_pointer = @ptrCast(request.request_data);
            stage.transfer_size = request.request_data_size;
        }

        stage.packets = @truncate((stage.transfer_size + packet_size - 1) / packet_size);
        stage.bytes_per_transaction = stage.transfer_size;
        stage.packets_per_transaction = stage.packets;
    } else {
        const temp_buffer = try self.allocator.alignedAlloc(u32, DMA_ALIGNMENT, 1);
        stage.buffer_pointer = @ptrCast(temp_buffer);
        stage.transfer_size = 0;
        stage.bytes_per_transaction = 0;
        stage.packets = 1;
        stage.packets_per_transaction = 1;
    }

    stage.state = @enumFromInt(0);
    stage.substate = @enumFromInt(0);

    // TODO consider frame schedulers for split/non-split,
    // periodic/non-periodic

    // TODO set a deadline on the stage_data for the transfer timeout

    return stage;
}

fn channelInterruptEnable(self: *Self, channel: ChannelId) void {
    self.host_registers.all_channel_interrupts_mask |= @as(u32, 1) << channel;
}

fn channelInterruptDisable(self: *Self, channel: ChannelId) void {
    self.host_registers.all_channel_interrupts_mask &= ~(@as(u32, 1) << channel);
}

fn transferStageAsync(self: *Self, request: *Request, in: bool, status_stage: bool, wait_block_assigned: u5) !void {
    const channel = try self.channelAllocate();

    std.log.debug("transfer stage async: in? {}, status? {}, ch {d}, waitblock {d}", .{ in, status_stage, channel, wait_block_assigned });

    const stage_data = try self.createStageData(channel, request, in, status_stage, wait_block_assigned);
    self.stage_data[channel] = stage_data;

    self.channelInterruptEnable(channel);

    // TODO handle split transfers
    stage_data.state = .no_split_transfer;

    try self.transactionStart(stage_data);
}

fn transactionStart(self: *Self, stage_data: *TransferStageData) !void {
    std.log.debug("transaction start on ch {d}", .{stage_data.channel});

    const channel = stage_data.channel;
    const channel_characteristics = self.channel_registers[channel].channel_character;

    // if the channel is enabled, we must disable it (and wait for
    // that to complete
    if (channel_characteristics.enable == 1) {
        std.log.debug("channel was enabled, must wait for disable", .{});
        stage_data.substate = .wait_for_channel_disable;
        self.channelStop(channel);
        // the rest happens when the interrupt fires
    } else {
        self.channelStart(stage_data);
    }
}

fn channelStart(self: *Self, stage: *TransferStageData) void {
    const channel = stage.channel;

    stage.substate = .wait_for_transaction_complete;

    // reset all pending channel interrupts
    self.channel_registers[channel].channel_int = @bitCast(@as(u32, 0xffff_ffff));

    // set transfer size, packet count, and pid
    const transfer_size: TransferSize = .{
        .transfer_size_bytes = stage.transferBytesRemaining(),
        .transfer_size_packets = stage.transferPacketsRemaining(),
        .pid = try stage.controllerPid(),
        .do_ping = 0,
    };
    self.channel_registers[channel].channel_transfer_size = transfer_size;

    // set DMA address
    self.channel_registers[channel].channel_dma_addr = @truncate(@intFromPtr(stage.addressDMA()));

    // TODO clear & inval data cache for [stage_data.addressDMA()..stage_data.addressDMA()+stage_data.transferBytesRemaining()]

    // set channel parameters
    var channel_characteristics = self.channel_registers[channel].channel_character;
    channel_characteristics.max_packet_size = stage.max_packet_size;
    channel_characteristics.multi_count = 1;

    if (stage.in) {
        channel_characteristics.endpoint_direction = .in;
    } else {
        channel_characteristics.endpoint_direction = .out;
    }

    switch (stage.speed) {
        .Low => channel_characteristics.low_speed_device = 1,
        else => channel_characteristics.low_speed_device = 0,
    }

    channel_characteristics.device_address = @truncate(stage.addressDevice());
    channel_characteristics.endpoint_type = stage.endpointType();
    channel_characteristics.endpoint_number = stage.endpointNumber();

    // TODO setup for periodic and split transactions
    channel_characteristics.odd_frame = 0;

    self.channel_registers[channel].channel_int_mask = @bitCast(stage.status_mask);

    channel_characteristics.enable = 1;
    channel_characteristics.disable = 0;

    self.channel_registers[channel].channel_character = channel_characteristics;
}

fn channelStop(self: *Self, channel: u5) void {
    std.log.debug("stopping channel {d}", .{channel});
    var channel_characteristics = self.channel_registers[channel].channel_character;
    channel_characteristics.enable = 0;
    channel_characteristics.disable = 1;
    self.channel_registers[channel].channel_character = channel_characteristics;
    self.channel_registers[channel].channel_int_mask = @bitCast(@as(u32, 0));
}

fn transferStage(self: *Self, request: *Request, in: bool, status_stage: bool) !void {
    const wait_until = self.deadline(request.timeout);

    const wait_block_assigned = try self.wait_block_allocations.allocate();

    if (self.wait_blocks[wait_block_assigned]) {
        return Error.ConfigurationError;
    }

    self.wait_blocks[wait_block_assigned] = true;
    try self.transferStageAsync(request, in, status_stage, wait_block_assigned);

    while (self.clock.ticks() < wait_until and self.wait_blocks[wait_block_assigned] == true) {
        // do nothing
    }

    if (self.wait_blocks[wait_block_assigned] == true) {
        // timeout elapsed... complain
        std.log.info("USB request timeout", .{});
        self.wait_blocks[wait_block_assigned] = false;
        self.wait_block_allocations.free(wait_block_assigned);
    }
}

fn requestSubmitBlocking(self: *Self, request: *Request) !void {
    request.status = 0;

    if (request.endpoint.type == usb.EndpointType.Control) {
        if (request.setup_data.request_type.transfer_direction == .device_to_host) {
            try self.transferStage(request, false, false);
            try self.transferStage(request, true, false);
            try self.transferStage(request, false, true);
            return;
        }
    }
}

fn descriptorQuery(
    self: *Self,
    endpoint: *Endpoint,
    descriptor_type: usb.DescriptorType,
    which: usb.DescriptorIndex,
    result: *align(64) usb.Descriptor,
    buffer_size: u16,
    request_type: usb.RequestType,
    index: u16,
) !void {
    std.log.debug("descriptor query for {any} on endpoint {d}", .{ descriptor_type, endpoint.number });

    const returned = try self.controlMessage(
        endpoint,
        request_type,
        @intFromEnum(usb.StandardDeviceRequests.get_descriptor),
        @as(u16, @intFromEnum(descriptor_type)) << 8 | @as(u8, which),
        index,
        result,
        buffer_size,
    );

    std.log.debug("descriptor query returned {any}", .{returned});

    if (returned != usb.DEFAULT_MAX_PACKET_SIZE) {
        return Error.InvalidResponse;
    }
}

// ----------------------------------------------------------------------
// USB Device Model
// ----------------------------------------------------------------------
const Function = struct {};

const Endpoint = struct {
    const EndpointDirection = enum {
        In,
        Out,
        InOut,
    };

    device: *Device,
    number: u4,
    type: usb.EndpointType = .Control,
    direction: EndpointDirection = .Out,
    max_packet_size: u11 = usb.DEFAULT_MAX_PACKET_SIZE,
    interval: u16 = DEFAULT_INTERVAL, // milliseconds
    next_pid: usb.PID = usb.PID.Setup,

    fn pidNext(self: *Endpoint, status_stage: bool) usb.PID {
        if (status_stage) {
            return usb.PID.Data1;
        } else {
            return self.next_pid;
        }
    }

    fn pidSkip(self: *Endpoint, packets: u16, status_stage: bool) void {
        // TODO should never occur with an Isochronous endpoint

        if (!status_stage) {
            switch (self.next_pid) {
                .Setup => self.next_pid = .Data1,
                .Data0 => {
                    if ((packets & 0x1) == 1) {
                        self.next_pid = .Data1;
                    }
                },
                .Data1 => {
                    if ((packets & 0x1) == 1) {
                        self.next_pid = .Data0;
                    }
                },
            }
        } else {
            // TODO should only occur with a Control endpoint
            self.next_pid = usb.PID.Setup;
        }
    }
};

const Device = struct {
    host: *Self,
    port: *RootPort,
    speed: usb.UsbSpeed,
    address: usb.Address,
    endpoint_0: Endpoint,
    function: [usb.MAX_FUNCTIONS]Function,
    hub_device: *Device,
    hub_address: u8,
    hub_port_number: u8,
    device_descriptor: usb.DeviceDescriptor,
    config_descriptor: usb.ConfigurationDescriptor,
    descriptor_buffer: DescriptorPtr,

    pub fn init(allocator: Allocator) !*Device {
        var device = try allocator.create(Device);

        device.address = usb.DEFAULT_ADDRESS;
        device.hub_address = 0;
        device.hub_port_number = 1;
        device.endpoint_0 = Endpoint{ .number = 0, .device = device };

        const raw_buffer = try allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(usb.Descriptor));
        device.descriptor_buffer = @ptrCast(raw_buffer);

        return device;
    }

    pub fn initialize(self: *Device, host: *Self, port: *RootPort, speed: usb.UsbSpeed) !void {
        self.host = host;
        self.port = port;
        self.speed = speed;

        try host.descriptorQuery(&self.endpoint_0, .device, usb.DEFAULT_DESCRIPTOR_INDEX, self.descriptor_buffer, usb.DEFAULT_MAX_PACKET_SIZE, usb.request_type_in, 0);
        try self.descriptor_buffer.expectDeviceDescriptor();
    }
};

const RootPort = struct {
    allocator: Allocator,
    host: *Self = undefined,
    device: *Device = undefined,
    enabled: bool = false,

    pub fn init(allocator: Allocator) RootPort {
        return .{
            .allocator = allocator,
            .host = undefined,
            .device = undefined,
        };
    }

    pub fn initialize(self: *RootPort, host: *Self) !void {
        self.host = host;

        try self.enable();
        try self.configureDevice();
        try self.overcurrentShutdownCheck();
    }

    fn enable(self: *RootPort) !void {
        if (!self.enabled) {
            // We should see the connect bit become true within 510 ms of
            // power on
            const connect_end = self.host.deadline(510);
            while (self.host.clock.ticks() <= connect_end and self.host.host_registers.port.connect == 0) {}

            self.host.delayMillis(100);

            // assert the reset bit for 50 millis
            var port = self.host.host_registers.port;
            port.connect_changed = 0;
            port.enabled = 0;
            port.enabled_changed = 0;
            port.overcurrent_changed = 0;
            port.reset = 1;
            self.host.host_registers.port = port;

            self.host.delayMillis(50);

            port = self.host.host_registers.port;
            port.connect_changed = 0;
            port.enabled = 0;
            port.enabled_changed = 0;
            port.overcurrent_changed = 0;
            port.reset = 0;
            self.host.host_registers.port = port;

            self.host.delayMillis(20);
            self.enabled = true;
        }
    }

    fn disable(self: *RootPort) !void {
        self.enabled = false;
    }

    fn configureDevice(self: *RootPort) !void {
        std.log.info("configure device start", .{});
        const speed = try self.host.getPortSpeed();

        self.device = try Device.init(self.allocator);
        self.device.initialize(self.host, self, speed) catch |err| {
            self.device = undefined;
            std.log.err("configure device error: {any}", .{err});
            return err;
        };
        std.log.info("configure device end", .{});
    }

    fn overcurrentShutdownCheck(self: *RootPort) !void {
        if (self.overcurrentDetected()) {
            self.disable() catch {};
            return Error.OvercurrentDetected;
        }
    }

    fn overcurrentDetected(self: *RootPort) bool {
        return self.host.host_registers.port.overcurrent == 1;
    }
};

// ----------------------------------------------------------------------
// Requests
// ----------------------------------------------------------------------

const Request = struct {
    setup_data: *align(DMA_ALIGNMENT) SetupPacket,
    endpoint: *Endpoint,
    request_data: *align(DMA_ALIGNMENT) anyopaque,
    request_data_size: u16,

    status: u32,
    result_length: u19,
    timeout: u16,

    fn init(
        allocator: Allocator,
        endpoint: *Endpoint,
        data: *align(DMA_ALIGNMENT) anyopaque,
        request_data_size: u16,
        setup_data: *align(DMA_ALIGNMENT) SetupPacket,
    ) !*Request {
        const request: *Request = try allocator.create(Request);

        request.* = .{
            .setup_data = setup_data,
            .endpoint = endpoint,
            .request_data = data,
            .request_data_size = request_data_size,
            .status = 0,
            .result_length = 0,
            .timeout = 100,
        };
        return request;
    }
};

// ----------------------------------------------------------------------
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_INTERVAL = 1;

pub const SetupPacket = extern struct {
    request_type: usb.RequestType,
    request: u8,
    value: u16,
    index: u16,
    length: u16,
};

pub const DMA_ALIGNMENT = 64;
pub const DescriptorPtr = *align(DMA_ALIGNMENT) usb.Descriptor;
