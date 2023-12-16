const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.dwc_otg_usb);

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
const Channel = @import("dwc/channel.zig");

const usb = @import("../usb.zig");
pub const DeviceAddress = usb.DeviceAddress;
pub const DeviceDescriptor = usb.DeviceDescriptor;
pub const TransactionStage = usb.TransactionStage;
pub const EndpointDirection = usb.EndpointDirection;
pub const EndpointNumber = usb.EndpointNumber;
pub const EndpointType = usb.EndpointType;
pub const PacketSize = usb.PacketSize;
pub const PID = usb.PID2;
pub const TransferBytes = usb.TransferBytes;
pub const UsbSpeed = usb.UsbSpeed;

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

const dwc_max_channels = 16;

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
    DataLengthMismatch,
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
channel_assignments: ChannelSet = ChannelSet.init("dwc_otg_usb channels", dwc_max_channels),
channels: [dwc_max_channels]Channel = [_]Channel{.{}} ** dwc_max_channels,
address_spinlock: Spinlock = Spinlock.init("usb address", true),
next_available_address: DeviceAddress = 1,
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
        log.err("USB init error: {any}", .{err});
        return 0;
    }
}

fn initializeRootPortShim(usb_controller: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);
    if (self.initializeRootPort()) |dev| {
        return @intFromPtr(dev);
    } else |err| {
        log.err("USB init root port error: {any}", .{err});
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
) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .allocator = allocator,
        .core_registers = @ptrFromInt(register_base),
        .host_registers = @ptrFromInt(register_base + 0x400),
        .power_and_clock_control = @ptrFromInt(register_base + 0xe00),
        .all_channel_intmask_lock = Spinlock.init("all channels interrupt mask", true),
        .intc = intc,
        .irq_id = irq_id,
        .translations = translations,
        .power_controller = power,
        .clock = clock,
        .root_port = RootPort.init(allocator),
        .num_host_channels = 0,
    };

    for (0..dwc_max_channels) |chid| {
        self.channels[chid].init(@truncate(chid), register_base + 0x500);
    }

    return self;
}

pub fn initialize(self: *Self) !void {
    try self.powerOn();
    try self.verifyHostControllerDevice();
    try self.globalInterruptDisable();
    try self.connectInterruptHandler();
    try self.initializeControllerCore();
    try self.enableCommonInterrupts();
    try self.globalInterruptEnable();
    try self.initializeHost();
}

fn powerOn(self: *Self) !void {
    const power_result = try self.power_controller.powerOn(.usb_hcd);

    if (power_result != .power_on) {
        log.err("Failed to power on USB device: {any}\n", .{power_result});
        return Error.PowerFailure;
    }
}

fn powerOff(self: *Self) !void {
    const power_result = try self.power_controller.powerOff(.usb_hcd);

    if (power_result != .power_off) {
        log.err("Failed to power off USB device: {any}\n", .{power_result});
        return Error.PowerFailure;
    }
}

fn verifyHostControllerDevice(self: *Self) !void {
    const id = self.core_registers.vendor_id;

    kprint("   DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

    if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
        log.warn(" gsnpsid = {x:0>8}\nvendor = {x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
        return Error.IncorrectDevice;
    }
}

fn globalInterruptDisable(self: *Self) !void {
    log.debug("global interrupt disable", .{});
    self.core_registers.ahb_config.global_interrupt_mask = 0;
}

fn globalInterruptEnable(self: *Self) !void {
    log.debug("global interrupt enable", .{});
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
        for (0..dwc_max_channels) |chid| {
            if ((all_intrs & channel_mask) != 0) {
                self.channels[chid].channelInterrupt();
            }
            channel_mask <<= 1;
        }
    }

    // clear the interrupt bits
    self.core_registers.core_interrupt_status = intr_status;
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
    log.info("host init start", .{});

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

    log.info("host init end", .{});
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

fn initializeRootPort(self: *Self) !*Device {
    log.info("root port init start", .{});
    defer log.info("root port init end", .{});

    return self.root_port.initialize(self);
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

fn channelAllocate(self: *Self) !*Channel {
    const chid = try self.channel_assignments.allocate();
    errdefer self.channel_assignments.free(chid);

    if (chid >= self.num_host_channels) {
        return Error.NoChannelAvailable;
    }
    return &self.channels[chid];
}

fn channelFree(self: *Self, channel: *Channel) void {
    self.channel_assignments.free(channel.id);
}

fn channelInterruptEnable(self: *Self, channel: Channel.ChannelId) void {
    log.debug("channel interrupt enable {d}", .{channel});

    self.all_channel_intmask_lock.acquire();
    defer self.all_channel_intmask_lock.release();
    self.host_registers.all_channel_interrupts_mask |= @as(u32, 1) << channel;
}

fn channelInterruptDisable(self: *Self, channel: Channel.ChannelId) void {
    log.debug("channel interrupt disable {d}", .{channel});

    self.all_channel_intmask_lock.acquire();
    defer self.all_channel_intmask_lock.release();
    self.host_registers.all_channel_interrupts_mask &= ~(@as(u32, 1) << channel);
}

// fn requestSubmitBlocking(self: *Self, request: *Request) !void {
//     request.status = 0;

//     if (request.endpoint.type == usb.EndpointType.Control) {
//         if (request.setup_data.request_type.transfer_direction == .device_to_host) {
//             try self.transferStage(request, false, false);
//             try self.transferStage(request, true, false);
//             try self.transferStage(request, false, true);
//             return;
//         }
//     }
// }

fn transactionOnChannel(
    self: *Self,
    device: DeviceAddress,
    device_speed: UsbSpeed,
    endpoint_number: EndpointNumber,
    endpoint_type: EndpointType,
    endpoint_direction: EndpointDirection,
    max_packet_size: PacketSize,
    initial_pid: usb.PID2,
    buffer: []u8,
    timeout: u32,
) !TransferBytes {
    var transaction = Transaction{
        .host = self,
        .deadline = if (timeout == 0) 0 else self.deadline(timeout),
        .actual_length = 0,
    };

    log.debug("Acquiring channel", .{});
    var channel = try self.channelAllocate();
    defer self.channelFree(channel);

    log.debug("Received channel {d}", .{channel.id});

    self.channelInterruptEnable(channel.id);
    defer self.channelInterruptDisable(channel.id);

    try channel.transactionBegin(device, device_speed, endpoint_number, endpoint_type, endpoint_direction, max_packet_size, initial_pid, buffer, &transaction.completion_handler);

    while (self.clock.ticks() < transaction.deadline and !transaction.completed) {}

    // wait for transaction.completed to be true, or deadline elapsed.
    if (transaction.completed) {
        return transaction.actual_length;
    } else {
        log.warn("Transaction timed out on channel {d}", .{channel.id});
        // if timeout, abort the transaction
        channel.channelAbort();

        try channel.waitForState(self.clock, .Idle, 100);

        return 0;
    }
}

const Transaction = struct {
    host: *Self,
    deadline: u64 = 0,
    completed: bool = false,
    actual_length: TransferBytes = 0,

    completion_handler: Channel.CompletionHandler = .{ .callback = onChannelComplete },

    // Callback invoked by `Channel.channelInterrupt`
    fn onChannelComplete(handler: *const Channel.CompletionHandler, channel: *Channel, data: []u8) void {
        log.debug("onChannelComplete for {d}", .{channel.id});

        var transaction: *Transaction = @constCast(@fieldParentPtr(Transaction, "completion_handler", handler));
        transaction.actual_length = @truncate(data.len);
        transaction.completed = true;
    }
};

fn controlTransfer(
    self: *Self,
    endpoint: *Endpoint,
    request_type: usb.RequestType,
    request: u8,
    value: u16,
    index: u16,
    data: []align(DMA_ALIGNMENT) u8,
    data_size: u16,
) !TransferBytes {
    var channel = try self.channelAllocate();
    defer self.channelFree(channel);

    const setup_slice: []SetupPacket = try self.allocator.alignedAlloc(SetupPacket, DMA_ALIGNMENT, 1);

    setup_slice[0] = .{
        .request_type = request_type,
        .request = request,
        .value = value,
        .index = index,
        .data_size = data_size,
    };

    // TODO this is too simplistic... it will fail if all channels are
    // occupied. A better way would be to enqueue a Request and have a
    // timer- or interrupt-driven dispatcher place transactions on
    // channels as when they are available.
    const device = endpoint.device;

    log.debug("controlTransfer: performing 'setup' transaction", .{});

    // TODO check return value, should equal max_packet_size (8) for
    // a Setup token packet to a Control endpoint
    const maybe_setup_response = self.transactionOnChannel(
        device.address,
        device.speed,
        endpoint.number,
        endpoint.type,
        EndpointDirection.out,
        endpoint.max_packet_size,
        .token_setup,
        std.mem.sliceAsBytes(setup_slice),
        100,
    );

    self.allocator.free(setup_slice);

    log.debug("controlTransfer: 'setup' transaction returned {any}", .{maybe_setup_response});

    const setup_response = try maybe_setup_response;

    if (setup_response != usb.DEFAULT_MAX_PACKET_SIZE) {
        return Error.InvalidResponse;
    }

    // Some requests don't have a data stage
    var in_data_response: u19 = 0;
    if (data.len > 0) {
        log.debug("controlTransfer: performing 'data' transaction with {any}", .{request_type.transfer_direction});

        const data_direction = switch (request_type.transfer_direction) {
            .host_to_device => EndpointDirection.out,
            .device_to_host => EndpointDirection.in,
        };

        const maybe_in_data_response = self.transactionOnChannel(
            device.address,
            device.speed,
            endpoint.number,
            endpoint.type,
            data_direction,
            endpoint.max_packet_size,
            .data_data0,
            data,
            100,
        );

        log.debug("controlTransfer: 'data' transaction returned {any}", .{maybe_in_data_response});

        in_data_response = try maybe_in_data_response;

        if (in_data_response != data.len) {
            return Error.DataLengthMismatch;
        }
    }

    log.debug("controlTransfer: performing 'status' transaction", .{});

    const maybe_status_response = self.transactionOnChannel(
        device.address,
        device.speed,
        endpoint.number,
        endpoint.type,
        EndpointDirection.in,
        endpoint.max_packet_size,
        .handshake_ack,
        &.{},
        100,
    );

    log.debug("controlTransfer: 'status' transaction returned {any}", .{maybe_status_response});

    _ = try maybe_status_response;

    return in_data_response;
}

fn descriptorQuery(
    self: *Self,
    endpoint: *Endpoint,
    descriptor_type: usb.DescriptorType,
    which: usb.DescriptorIndex,
    result: []align(64) u8,
    buffer_size: u16,
    index: u16,
) !void {
    log.debug("descriptor query for {any} on device {d} endpoint {d}", .{ descriptor_type, endpoint.device.address, endpoint.number });

    const returned = try self.controlTransfer(
        endpoint,
        usb.request_type_in,
        @intFromEnum(usb.StandardDeviceRequests.get_descriptor),
        @as(u16, @intFromEnum(descriptor_type)) << 8 | @as(u8, which),
        index,
        result,
        buffer_size,
    );

    log.debug("descriptor query returned {any}", .{returned});

    if (returned != buffer_size) {
        log.debug("expected {d}, got {d}", .{ buffer_size, returned });
        return Error.InvalidResponse;
    }
}

fn addressSet(
    self: *Self,
    endpoint: *Endpoint,
    address: DeviceAddress,
) !u19 {
    log.debug("set address {d} on endpoint {d}", .{ address, endpoint.number });

    const unused: []align(DMA_ALIGNMENT) u8 = &.{};

    const ret = self.controlTransfer(
        endpoint,
        usb.request_type_out,
        @intFromEnum(usb.StandardDeviceRequests.set_address),
        address,
        0,
        unused,
        0,
    );

    log.debug("set address {d} on endpoint {d} returned {any}", .{ address, endpoint.number, ret });

    return ret;
}

// ----------------------------------------------------------------------
// USB Device Model
// ----------------------------------------------------------------------
const Function = struct {};

const Endpoint = struct {
    device: *Device,
    number: u4,
    type: usb.EndpointType = .Control,
    direction: EndpointDirection = .out,
    max_packet_size: u11 = usb.DEFAULT_MAX_PACKET_SIZE,
};

pub const Device = struct {
    allocator: Allocator,
    host: *Self,
    port: *RootPort,
    speed: usb.UsbSpeed,
    address: usb.DeviceAddress,
    endpoint_0: Endpoint,
    device_descriptor: usb.DeviceDescriptor,
    config_descriptor: usb.ConfigurationDescriptor,

    pub fn init(allocator: Allocator) !*Device {
        var device = try allocator.create(Device);

        device.* = .{
            .allocator = allocator,
            .host = undefined,
            .port = undefined,
            .speed = undefined,
            .address = usb.DEFAULT_ADDRESS,
            .endpoint_0 = .{ .number = 0, .device = device },
            .device_descriptor = undefined,
            .config_descriptor = undefined,
        };

        return device;
    }

    pub fn initialize(self: *Device, host: *Self, port: *RootPort, speed: usb.UsbSpeed) !void {
        self.host = host;
        self.port = port;
        self.speed = speed;

        const expected_size = usb.descriptorExpectedSize(.device);
        var descriptor_buffer: []align(DMA_ALIGNMENT) u8 = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, expected_size);
        defer self.allocator.free(descriptor_buffer);

        log.debug("Device descriptor query, buffer at 0x{x:0>8}", .{@intFromPtr(descriptor_buffer.ptr)});

        try host.descriptorQuery(&self.endpoint_0, .device, usb.DEFAULT_DESCRIPTOR_INDEX, descriptor_buffer, expected_size, 0);

        // sanity check the response,
        if (DeviceDescriptor.fromSlice(descriptor_buffer)) |desc| {
            // copy the struct contents (it's still in the []u8
            // allocated above)
            self.device_descriptor = desc.*;

            self.device_descriptor.dump();

            var my_address: DeviceAddress = undefined;
            {
                host.address_spinlock.acquire();
                defer host.address_spinlock.release();

                my_address = host.next_available_address;
                host.next_available_address += 1;

                log.debug("Claimed address {d}", .{my_address});
            }

            _ = try host.addressSet(&self.endpoint_0, my_address);
            self.address = my_address;

            // wait 2 ms for the device to actually change its address
            host.delayMillis(2);
        } else |err| {
            log.err("descriptorQuery returned something unexpected {any}", .{err});
            return err;
        }
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

    pub fn initialize(self: *RootPort, host: *Self) !*Device {
        self.host = host;

        try self.enable();
        try self.configureDevice();
        try self.overcurrentShutdownCheck();

        return self.device;
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
        log.info("configure device start", .{});
        const speed = try self.host.getPortSpeed();

        self.device = try Device.init(self.allocator);
        self.device.initialize(self.host, self, speed) catch |err| {
            self.device = undefined;
            log.err("configure device error: {any}", .{err});
            return err;
        };
        log.info("configure device end", .{});
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
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_INTERVAL = 1;

pub const SetupPacket = extern struct {
    request_type: usb.RequestType,
    request: u8,
    value: u16,
    index: u16,
    data_size: u16,
};

pub const DMA_ALIGNMENT = 64;
pub const DescriptorPtr = *align(DMA_ALIGNMENT) usb.Descriptor;
