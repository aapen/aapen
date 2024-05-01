const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const PendingTransfers = DoublyLinkedList(*TransferRequest);

const root = @import("root");
const HAL = root.HAL;
const InterruptController = HAL.InterruptController;
const IrqId = InterruptController.IrqId;
const IrqHandlerFn = InterruptController.IrqHandlerFn;
const IrqHandler = InterruptController.IrqHandler;
const memory_map = HAL.memory_map;
const PowerController = HAL.PowerController;
const POWER_DEVICE_USB_HCD = PowerController.POWER_DEVICE_USB_HCD;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const atomic = @import("../atomic.zig");

const debug = @import("../debug.zig");

const ChannelSet = @import("../channel_set.zig");

const Forth = @import("../forty/forth.zig").Forth;

const Logger = @import("../logger.zig");
pub var log: *Logger = undefined;

const mailbox = @import("../mailbox.zig");
const Mailbox = mailbox.Mailbox;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const schedule = @import("../schedule.zig");

const semaphore = @import("../semaphore.zig");

const synchronize = @import("../synchronize.zig");
const OneShot = synchronize.OneShot;
const TicketLock = synchronize.TicketLock;

const time = @import("../time.zig");

const usb = @import("../usb.zig");
const SetupPacket = usb.SetupPacket;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferType = usb.TransferType;
const UsbSpeed = usb.UsbSpeed;
const USB_FRAMES_PER_MS = usb.FRAMES_PER_MS;
const USB_UFRAMES_PER_MS = usb.UFRAMES_PER_MS;

const reg = @import("dwc/registers.zig");
const RootHub = @import("dwc/root_hub.zig");

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

const dwc_max_channels = 16;

const Self = @This();

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

pub const Error = error{
    IncorrectDevice,
    InitializationFailure,
    PowerFailure,
    ConfigurationError,
    OvercurrentDetected,
    InvalidResponse,
    DataLengthMismatch,
    NoDevice,
};

// ----------------------------------------------------------------------
// Channel Registers
// ----------------------------------------------------------------------
pub const ChannelCharacteristics = reg.ChannelCharacteristics;
pub const SplitControl = reg.SplitControl;
pub const ChannelInterrupt = reg.ChannelInterrupt;
pub const DwcTransferSizePid = reg.DwcTransferSizePid;
pub const TransferSize = reg.Transfer;
pub const ChannelRegisters = reg.ChannelRegisters;

// ----------------------------------------------------------------------
// Host Registers
// ----------------------------------------------------------------------
pub const HostConfig = reg.HostConfig;
pub const HostFrameInterval = reg.HostFrameInterval;
pub const HostFrames = reg.HostFrames;
pub const HostPeriodicFifo = reg.PeriodicFifoStatus;
pub const HostNonPeriodicFifo = reg.NonPeriodicFifoStatus;
pub const HostPort = reg.HostPortStatusAndControl;
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
pub const FifoSize = reg.FifoSize;
pub const NonPeriodicFifoStatus = reg.NonPeriodicFifoStatus;
pub const GeneralCoreConfig = reg.GeneralCoreConfig;
pub const HwConfig2 = reg.HwConfig2;
pub const HwConfig3 = reg.HwConfig3;
pub const HwConfig4 = reg.HwConfig4;
pub const CoreRegisters = reg.CoreRegisters;
pub const PowerAndClock = reg.PowerAndClock;
pub const HighSpeedPhyType = reg.HighSpeedPhyType;

// ----------------------------------------------------------------------
// HCD state
// ----------------------------------------------------------------------
pub const DEFAULT_TRANSFER_TIMEOUT = 1000;
pub const DEFAULT_INTERVAL = 1;
pub const DMA_ALIGNMENT: usize = 64;

const HcdChannels = ChannelSet.init("dwc_otg_usb channels", u5, dwc_max_channels);
const UsbTransferMailbox = Mailbox(*TransferRequest);

const empty_slice: []u8 = &[_]u8{};

const register_base: u64 = root.HAL.peripheral_base + 0x980_000;
const core: *volatile CoreRegisters = @ptrFromInt(register_base);
const host: *volatile HostRegisters = @ptrFromInt(register_base + 0x400);
const channel_base: u64 = register_base + 0x500;
const power: *volatile PowerAndClock = @ptrFromInt(register_base + 0xe00);
var power_controller: *PowerController = undefined;

var driver_thread: schedule.TID = schedule.NO_TID;
var shutdown_signal: OneShot = .{};
var transfer_mailbox: UsbTransferMailbox = undefined;

var root_hub: RootHub = .{};
var num_host_channels: u4 = 0;

var interrupt_controller: *InterruptController = undefined;
var irq_id: IrqId = 0;
var irq_handler: IrqHandler = irqHandle;

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "dumpStatus", "usb-hci-status" },
        .{ "channelStatus", "usb-channel-status" },
    });
}

// ----------------------------------------------------------------------
// Core interface layer: Initialization
// ----------------------------------------------------------------------
pub fn init(
    allocator: Allocator,
    intc: *InterruptController,
    ii: IrqId,
    power_ctrl: *PowerController,
) !*Self {
    log = Logger.init("dwc2", .info);

    const self = try allocator.create(Self);
    self.* = .{};

    power_controller = power_ctrl;

    root_hub.init(host);

    interrupt_controller = intc;
    irq_id = ii;

    // for (0..dwc_max_channels) |chid| {
    //     channels[chid].init(
    //         chid,
    //         channelRegisters(@truncate(chid)),
    //         &channel_buffers[chid],
    //     );
    // }

    try transfer_mailbox.init(allocator, 1024);

    return self;
}

pub fn initialize(self: *Self) !void {
    _ = self;

    try powerOn();
    try verifyHostControllerDevice();
    try coreReset();
    try initializeControllerCore();
    try initializeInterrupts();

    // higher priority so it gets scheduled ahead of the application
    // thread
    const DRIVER_THREAD_PRIO = 200;
    driver_thread = try schedule.spawnWithOptions(dwcDriverLoop, &.{}, &.{
        .name = "dwc driver",
        .priority = DRIVER_THREAD_PRIO,
        .schedule = false,
    });
}

fn powerOn() !void {
    const power_result = try power_controller.powerOn(POWER_DEVICE_USB_HCD);

    if (power_result != .power_on) {
        log.err(@src(), "Failed to power on USB device: {any}", .{power_result});
        return error.PowerFailure;
    }

    // wait a bit for power to settle
    time.delayMillis(10);
}

fn powerOff() !void {
    const power_result = try power_controller.powerOff(POWER_DEVICE_USB_HCD);

    if (power_result != .power_off) {
        log.err(@src(), "Failed to power off USB device: {any}", .{power_result});
        return Error.PowerFailure;
    }
}

fn verifyHostControllerDevice() !void {
    const id = core.vendor_id;

    log.info(@src(), "Core registers at 0x{x:0>8}", .{@intFromPtr(core)});
    log.info(@src(), "DWC2 OTG core rev: {x}.{x:0>3}", .{ id.device_series, id.device_minor_rev });

    if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
        log.warn(@src(), " gsnpsid = 0x{x:0>8}, vendor = 0x{x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
        return error.IncorrectDevice;
    }

    const hwcfg = core.hardware_config_2;
    const fs_phy_type = hwcfg.full_speed_physical_type;
    const hs_phy_type = hwcfg.high_speed_physical_type;
    const dma_support = hwcfg.dma_architecture;
    const endpoints = hwcfg.num_device_endpoints;
    const num_channels = hwcfg.num_host_channels;

    log.debug(@src(), "operating mode: {s}", .{
        @tagName(hwcfg.operating_mode),
    });

    log.debug(@src(), "hsphy type: {s}, fsphy type: {s}, dma support: {s}", .{
        @tagName(hs_phy_type),
        @tagName(fs_phy_type),
        @tagName(dma_support),
    });

    log.debug(@src(), "enpoints: {d}, channels: {d}", .{
        endpoints,
        num_channels,
    });
}

/// Returns true if the physical interface supports USB high-speed connections
fn isPhyHighSpeedSupported() bool {
    return core.hardware_config_2.high_speed_physical_type != .not_supported;
}

/// Initialize the physical interface for USB high-speed connection
fn phyHighSpeedInit() !void {
    var usb_config = core.usb_config;

    // deselect full-speed phy
    usb_config.phy_sel = 0;

    if (core.hardware_config_2.high_speed_physical_type == .ulpi) {
        log.debug(@src(), "High-speed ULPI PHY init", .{});

        usb_config.mode_select = .ulpi;
        usb_config.phy_if_16 = ._8_bit;
        usb_config.ddr_sel = 0;
        usb_config.ulpi_ext_vbus_drv = 0;
        usb_config.ulpi_ext_vbus_indicator = 0;
        usb_config.ulpi_fsls = 0;
        usb_config.ulpi_clk_sus_m = 0;
    } else {
        log.debug(@src(), "High-speed UTMI+ PHY init", .{});
        usb_config.mode_select = .utmi_plus;

        usb_config.phy_if_16 = switch (core.hardware_config_4.utmi_physical_data_width) {
            .width_8_bit => ._8_bit,
            .width_16_bit => ._16_bit,
            .width_32_bit => ._16_bit, // not sure about this
        };
    }

    // write config to register
    core.usb_config = usb_config;

    try coreReset();

    // set turnaround time. can only be done after core reset
    usb_config.usb_trdtim = switch (core.hardware_config_4.utmi_physical_data_width) {
        .width_16_bit => 5,
        else => 9,
    };

    core.usb_config = usb_config;
}

fn phyFullSpeedInit() !void {
    log.debug(@src(), "Full-speed PHY init", .{});

    var usb_config = core.usb_config;
    usb_config.phy_sel = 1;
    core.usb_config = usb_config;

    try coreReset();

    // set turnaround time. can only be done after core reset
    usb_config.usb_trdtim = 5;
    core.usb_config = usb_config;
}

fn initializeControllerCore() !void {
    if (isPhyHighSpeedSupported()) {
        try phyHighSpeedInit();
    } else {
        try phyFullSpeedInit();
    }

    num_host_channels = core.hardware_config_2.num_host_channels;

    power.* = @bitCast(@as(u32, 0));

    try configPhyClockSpeed();

    const rx_words: u32 = 1024; // Size of Rx FIFO in 4-byte words
    const tx_words: u32 = 1024; // Size of Non-periodic Tx FIFO in 4-byte words
    const ptx_words: u32 = 1024; // Size of Periodic Tx FIFO in 4-byte words

    // Configure FIFO sizes. Required because the defaults do not work correctly.
    core.rx_fifo_size = @bitCast(rx_words);
    core.nonperiodic_tx_fifo_size = @bitCast((tx_words << 16) | rx_words);
    core.host_periodic_tx_fifo_size = @bitCast((ptx_words << 16) | (rx_words + tx_words));

    try txFifoFlush(0x10);
    try rxFifoFlush();

    var ahb = core.ahb_config;
    ahb.dma_enable = 1;
    ahb.dma_remainder_mode = .incremental;
    ahb.wait_for_axi_writes = 1;
    ahb.max_axi_burst = 0;
    core.ahb_config = ahb;

    var usb_config = core.usb_config;
    switch (core.hardware_config_2.operating_mode) {
        .hnp_srp_capable_otg => {
            usb_config.hnp_capable = 1;
            usb_config.srp_capable = 1;
        },
        .srp_only_capable_otg, .srp_capable_device, .srp_capable_host => {
            usb_config.hnp_capable = 0;
            usb_config.srp_capable = 1;
        },
        .no_hnp_src_capable_otg, .no_srp_capable_host, .no_srp_capable_device => {
            usb_config.hnp_capable = 0;
            usb_config.srp_capable = 0;
        },
        else => {
            usb_config.hnp_capable = 0;
            usb_config.srp_capable = 0;
        },
    }
    core.usb_config = usb_config;
}

fn coreReset() !void {
    // log.debug(@src(), "core controller reset", .{});

    // trigger the soft reset
    core.reset.soft_reset = 1;

    // wait up to 10 ms for reset to finish
    const reset_end = time.deadlineMillis(10);

    while (time.ticks() < reset_end and core.reset.soft_reset != 0) {}

    if (core.reset.soft_reset != 0) {
        return Error.InitializationFailure;
    }

    // wait for AHB master to go idle
    const ahb_idle_wait_end = time.deadlineMillis(10);

    while (time.ticks() < ahb_idle_wait_end and core.reset.ahb_master_idle == 0) {}

    if (core.reset.ahb_master_idle != 1) {
        return Error.InitializationFailure;
    }
}

fn initializeInterrupts() !void {
    // Clear pending interrupts
    const clear_all: InterruptStatus = @bitCast(@as(u32, 0xffff_ffff));
    core.core_interrupt_status = clear_all;

    // Clear the channel interrupts mask and any pending interrupt bits
    host.all_channel_interrupts_mask = @bitCast(@as(u32, 0));
    host.all_channel_interrupts = @bitCast(clear_all);

    // Connect interrupt handler & enable interrupts on the ARM PE
    interrupt_controller.connect(irq_id, &irq_handler, &.{});
    interrupt_controller.enable(irq_id);

    // Enable only host channel and port interrupts
    var enabled: InterruptMask = @bitCast(@as(u32, 0));
    enabled.host_channel = 1;
    enabled.port = 1;
    core.core_interrupt_mask = enabled;

    // Enable interrupts for the host controller (this is the DWC side)
    core.ahb_config.global_interrupt_enable = 1;

    log.debug(@src(), "initializeInterrupts: mask = 0x{x:0>8}, status = 0x{x:0>8}", .{
        @as(u32, @bitCast(core.core_interrupt_mask)),
        @as(u32, @bitCast(core.core_interrupt_status)),
    });
}

fn configPhyClockSpeed() !void {
    const core_config = core.usb_config;
    const hw2 = core.hardware_config_2;
    if (hw2.high_speed_physical_type == .ulpi and hw2.full_speed_physical_type == .dedicated and core_config.ulpi_fsls == 1) {
        host.config.clock_rate = .clock_48_mhz;
    } else {
        host.config.clock_rate = .clock_30_60_mhz;
    }
}

fn txFifoFlush(fifo_num: u5) !void {
    const flush: Reset = .{
        .tx_fifo_flush = 1,
        .tx_fifo_flush_num = fifo_num,
    };
    core.reset = flush;

    const flush_wait_end = time.deadlineMillis(100);
    while (core.reset.tx_fifo_flush == 1 and time.ticks() < flush_wait_end) {}

    // TODO return error if timeout hit without seeing tx_fifo_flush
    // go low.
}

fn rxFifoFlush() !void {
    const flush: Reset = .{
        .rx_fifo_flush = 1,
    };
    core.reset = flush;
    const flush_wait_end = time.deadlineMillis(100);
    while (core.reset.rx_fifo_flush == 1 and time.ticks() < flush_wait_end) {}

    // TODO return error if timeout hit without seeing rx_fifo_flush
    // go low.
}

// ----------------------------------------------------------------------
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(_: *InterruptController, _: IrqId, _: ?*anyopaque) void {
    _ = atomic.atomicReset(&schedule.resdefer, 1);

    const intr_status = core.core_interrupt_status;

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel == 1) {
        const all_intrs = host.all_channel_interrupts;
        //        host.all_channel_interrupts = all_intrs;
        log.debug(@src(), "irq handle: host channel ints 0x{x:0>8}", .{@as(u32, @bitCast(all_intrs))});

        // Find the channel that has something to say
        var channel_mask: u32 = 1;
        // TODO consider using @ctz to find the lowest bit that's set,
        // instead of looping over all 16 channels.
        for (0..dwc_max_channels) |chid| {
            if ((all_intrs & channel_mask) != 0) {
                channelInterrupt(@truncate(chid));
            }
            channel_mask <<= 1;
        }
    }

    // check if the host port raised the interrupt
    if (intr_status.port == 1) {
        // pass it on to the root hub
        root_hub.hubHandlePortInterrupt();
    }

    // clear the interrupt bits
    core.core_interrupt_status = intr_status;

    const prior = atomic.atomicDec(&schedule.resdefer);
    if (prior > 1) {
        // `resdefer` gets incremented each time a thread _attempts_
        // to reschedule while rescheduling is deferred. If it is > 0
        // after we decrement it (meaning it was > 1 _before_ we
        // decremented), then we have a pending need to reschedule
        _ = atomic.atomicReset(&schedule.resdefer, 0);
        schedule.reschedule();
    }
}

pub fn dumpStatus() void {
    log.info(@src(), "{s: >28}", .{"Core registers"});
    dumpRegisterPair("otg_control", @bitCast(core.otg_control), "ahb_config", @bitCast(core.ahb_config));
    dumpRegisterPair("usb_config", @bitCast(core.usb_config), "reset", @bitCast(core.reset));
    dumpRegisterPair("hw_config_1", @bitCast(core.hardware_config_1), "hw_config_2", @bitCast(core.hardware_config_2));
    dumpRegisterPair("interrupt_status", @bitCast(core.core_interrupt_status), "interrupt_mask", @bitCast(core.core_interrupt_mask));
    dumpRegisterPair("rx_status", @bitCast(core.rx_status_read), "rx_fifo_size", @bitCast(core.rx_fifo_size));
    dumpRegisterPair("nonperiodic_tx_fifo_size", @bitCast(core.nonperiodic_tx_fifo_size), "nonperiodic_tx_status", @bitCast(core.nonperiodic_tx_status));

    log.info(@src(), "", .{});
    log.info(@src(), "{s: >28}", .{"Host registers"});
    dumpRegisterPair("port", @bitCast(host.port), "config", @bitCast(host.config));
    dumpRegisterPair("frame_interval", @bitCast(host.frame_interval), "frame_num", @bitCast(host.frame_num));
    dumpRegisterPair("all_channel_interrupts", @bitCast(host.all_channel_interrupts), "all_channel_interrupts_mask", @bitCast(host.all_channel_interrupts_mask));
}

pub fn channelStatus(chid: u64) void {
    log.info(@src(), "{s: >28}", .{"Channel registers"});
    dumpRegisterPair("characteristics", @bitCast(channel_registers[chid].channel_character), "split_control", @bitCast(channel_registers[chid].split_control));
    dumpRegisterPair("interrupt", @bitCast(channel_registers[chid].channel_int), "int. mask", @bitCast(channel_registers[chid].channel_int_mask));
    dumpRegisterPair("transfer", @bitCast(channel_registers[chid].transfer), "dma addr", @bitCast(channel_registers[chid].channel_dma_addr));
}

pub fn dumpRegisterPair(f1: []const u8, v1: u32, f2: []const u8, v2: u32) void {
    log.info(@src(), "{s: >28}: {x:0>8}\t{s: >28}: {x:0>8}", .{ f1, v1, f2, v2 });
}

fn dumpRegister(field_name: []const u8, v: u32) void {
    log.info(@src(), "{s: >28}: {x:0>8}", .{ field_name, v });
}

// ----------------------------------------------------------------------
// Channel handling
// ----------------------------------------------------------------------

var channel_assignments: HcdChannels = .{};
//var channels: [dwc_max_channels]Channel = [_]Channel{.{}} ** dwc_max_channels;
var channel_buffers: [dwc_max_channels][1024]u8 align(DMA_ALIGNMENT) = [_][1024]u8{.{0} ** 1024} ** dwc_max_channels;

const ChannelId = u5;

var active_transfer: [dwc_max_channels]?*TransferRequest = init: {
    var initial_value: [dwc_max_channels]?*TransferRequest = undefined;
    for (0..dwc_max_channels) |chid| {
        initial_value[chid] = null;
    }
    break :init initial_value;
};

var channel_registers: [dwc_max_channels]*volatile ChannelRegisters = init: {
    var initial_value: [dwc_max_channels]*volatile ChannelRegisters = undefined;
    for (0..dwc_max_channels) |chid| {
        initial_value[chid] = channelRegisters(chid);
    }
    break :init initial_value;
};

fn channelRegisters(chid: ChannelId) *volatile ChannelRegisters {
    return @ptrFromInt(channel_base + (@sizeOf(ChannelRegisters) * @as(usize, chid)));
}

fn channelAllocate() !ChannelId {
    const chid = try channel_assignments.allocate();
    errdefer channel_assignments.free(chid);

    if (chid >= num_host_channels) {
        return error.NoAvailableChannel;
    }

    return chid;
}

pub fn channelFree(channel: ChannelId) void {
    channel_assignments.free(channel);
}

// ----------------------------------------------------------------------
// Managing aligned buffers
// ----------------------------------------------------------------------
pub fn isAligned(ptr: [*]u8) bool {
    return (@intFromPtr(ptr) & (DMA_ALIGNMENT - 1) == 0);
}

// ----------------------------------------------------------------------
// Transfer interface - high level
// ----------------------------------------------------------------------

// this is called from application threads
pub fn perform(_: *Self, xfer: *TransferRequest) !void {
    // put the transfer in the pending_transfers list.
    try transfer_mailbox.send(xfer);
}

fn calculatePacketCount(input_size_in: TransferBytes, ep_dir: u1, ep_mps: u16) TransferSize {
    var input_size = input_size_in;
    var num_packets: u32 = (input_size + ep_mps - 1) / ep_mps;

    if (num_packets > 256) {
        num_packets = 256;
    }

    if (input_size == 0) {
        num_packets = 1;
    }

    if (ep_dir == usb.USB_ENDPOINT_DIRECTION_IN) {
        input_size = @truncate(num_packets * ep_mps);
    }

    return TransferSize{
        .packet_count = @truncate(num_packets),
        .size = input_size,
        .packet_id = DwcTransferSizePid.data1,
        .do_ping = 0,
    };
}

/// Start or restart a transfer on a channel of the HCD
pub fn channelStartTransfer(id: ChannelId, req: *TransferRequest) void {
    var characteristics: ChannelCharacteristics = @bitCast(@as(u32, 0));
    var split_control: SplitControl = @bitCast(@as(u32, 0));
    var transfer: TransferSize = @bitCast(@as(u32, 0));
    var data: ?[*]u8 = null;

    req.short_attempt = false;

    if (req.endpoint_desc) |ep| {
        characteristics.endpoint_number = @truncate(ep.endpoint_address & 0xf);
        characteristics.endpoint_type = ep.getType();
        characteristics.max_packet_size = @truncate(ep.max_packet_size & 0x7ff);
        characteristics.packets_per_frame = 1;
        if (req.device != null and req.device.?.speed == UsbSpeed.High) {
            characteristics.packets_per_frame += @truncate((ep.max_packet_size >> 11) & 0x3);
        }

        log.debug(@src(), "channel start transfer to endpoint {d} mps {d}", .{ characteristics.endpoint_number, characteristics.max_packet_size });
    } else {
        // This transfer aims at the default control
        // endpoint. (Endpoint 0.)
        log.debug(@src(), "channel start transfer to default control endpoint", .{});
        characteristics.endpoint_number = 0;
        characteristics.endpoint_type = TransferType.control;
        characteristics.max_packet_size = req.device.?.device_descriptor.max_packet_size;
        characteristics.packets_per_frame = 1;
    }

    var input_size: TransferBytes = 0;
    var next_pid: u2 = DwcTransferSizePid.data1;

    if (characteristics.endpoint_type == TransferType.control) {
        switch (req.control_phase) {
            TransferRequest.control_setup_phase => {
                debugLogTransfer(req, "starting SETUP transaction");
                characteristics.endpoint_direction = usb.USB_ENDPOINT_DIRECTION_OUT;
                data = @ptrCast(&req.setup_data);
                input_size = @sizeOf(SetupPacket);
                next_pid = DwcTransferSizePid.setup;

                // transfer.size = @sizeOf(SetupPacket);
                // transfer.packet_id = DwcTransferSizePid.setup;

                log.sliceDump(@src(), std.mem.asBytes(&req.setup_data));
            },
            TransferRequest.control_data_phase => {
                debugLogTransfer(req, "starting DATA transaction");
                characteristics.endpoint_direction = @truncate((req.setup_data.request_type >> 7) & 0b1);
                data = req.data + req.actual_size;
                input_size = @truncate(req.size - req.actual_size);
                next_pid = if (req.actual_size == 0) DwcTransferSizePid.data1 else req.next_data_pid;

                // transfer.size = @truncate(req.size - req.actual_size);
                // if (req.actual_size == 0) {
                //     // the first data packet is always DATA1
                //     transfer.packet_id = DwcTransferSizePid.data1;
                // } else {
                //     // subsequent data packets alternate DATA0/1
                //     transfer.packet_id = req.next_data_pid;
                // }
            },
            else => {
                debugLogTransfer(req, "starting STATUS transaction");

                const dir = (req.setup_data.request_type >> 7) & 0b1;
                if (dir == usb.USB_ENDPOINT_DIRECTION_OUT or req.setup_data.data_size == 0) {
                    characteristics.endpoint_direction = usb.USB_ENDPOINT_DIRECTION_IN;
                } else {
                    characteristics.endpoint_direction = usb.USB_ENDPOINT_DIRECTION_OUT;
                }
                data = null;
                input_size = 0;
                next_pid = DwcTransferSizePid.data1;

                // transfer.size = 0;
                // transfer.packet_id = DwcTransferSizePid.data1;
            },
        }
    } else {
        // non-control transfer, either starting for the first time or
        // restarting (maybe after being deferred)
        characteristics.endpoint_direction = req.endpoint_desc.?.direction();
        data = req.data + req.actual_size;
        input_size = @truncate(req.size - req.actual_size);
        next_pid = req.next_data_pid;

        // transfer.size = @truncate(req.size - req.actual_size);

        if (characteristics.endpoint_type == TransferType.interrupt) {
            if (input_size > characteristics.packets_per_frame * characteristics.max_packet_size) {
                input_size = characteristics.packets_per_frame * characteristics.max_packet_size;
                req.short_attempt = true;
            }

            // if (transfer.size > characteristics.packets_per_frame * characteristics.max_packet_size) {
            //     transfer.size = characteristics.packets_per_frame * characteristics.max_packet_size;
            //     req.short_attempt = true;
            // }
            // else {
            //     const mps = characteristics.max_packet_size;
            //     transfer.size = @truncate((transfer.size + mps - 1) / mps);
            // }
        }

        //        transfer.packet_id = req.next_data_pid;

        debugLogTransfer(req, "starting transaction");
    }

    transfer = calculatePacketCount(input_size, characteristics.endpoint_direction, characteristics.max_packet_size);
    transfer.packet_id = next_pid;

    characteristics.device_address = req.device.?.address;

    // if talking to a low or full speed device, handle the
    // split register
    // if (req.device.?.speed != UsbSpeed.High) {
    //     // log.debug(@src(),"device needs a split transaction, finding TT", .{});

    //     // find which hub is the transaction translator (TT)
    //     var tt_hub_port: u7 = 0;
    //     var tt_hub: ?*Device = req.device.?;

    //     // TODO - is this guaranteed to finish?
    //     while (tt_hub != null and tt_hub.?.speed != UsbSpeed.High) {
    //         tt_hub_port = tt_hub.?.parent_port;
    //         tt_hub = tt_hub.?.parent;
    //     }

    //     split_control.port_address = if (tt_hub_port >= 1) tt_hub_port - 1 else 0;
    //     split_control.hub_address = if (tt_hub) |h| h.address else 0;
    //     split_control.split_enable = 1;
    //     split_control.transaction_position = 0b11;

    //     // log.debug(@src(),"split control: port {d}, hub {d}, enable {d}", .{ split_control.port_address, split_control.hub_address, split_control.split_enable });

    //     if (transfer.size > characteristics.max_packet_size) {
    //         transfer.size = characteristics.max_packet_size;
    //         req.short_attempt = true;
    //     }

    //     characteristics.low_speed_device = switch (req.device.?.speed) {
    //         .Low => 1,
    //         else => 0,
    //     };
    // }

    const registers = channel_registers[id];

    if (data == null) {
        registers.channel_dma_addr = 0;
    } else if (isAligned(data.?)) {
        registers.channel_dma_addr = @truncate(@intFromPtr(data.?));
    } else {
        registers.channel_dma_addr = @truncate(@intFromPtr(&channel_buffers[id]));

        // the aligned buffer is a fixed size, so it might not be big
        // enough to hold the entire transmission. we will do as much
        // as possible
        const buflen = channel_buffers[id].len;
        if (transfer.size > buflen) {
            const max_full_packets = buflen - (buflen % characteristics.max_packet_size);
            transfer.size = @truncate(max_full_packets);
            req.short_attempt = true;
        }

        // if we are sending data, copy it into the aligned buffer
        if (characteristics.endpoint_direction == 0) {
            @memcpy(channel_buffers[id][0..transfer.size], data.?);
        }
    }

    if (registers.channel_dma_addr != 0 and req.size > 0) {
        synchronize.dataCacheRangeCleanAndInvalidate(registers.channel_dma_addr, req.size);
    }

    // It's OK if this doesn't match the DMA address selected
    // above. We mostly use this to track the # of bytes remaining to
    // send or receive
    req.cur_data_ptr = data;

    if (registers.channel_dma_addr & (DMA_ALIGNMENT - 1) != 0) {
        log.warn(@src(), "data ptr 0x{x:0>8} misaligned by 0x{x} bytes", .{ registers.channel_dma_addr, (registers.channel_dma_addr & (DMA_ALIGNMENT - 1)) });
    }

    // const mps = characteristics.max_packet_size;
    // transfer.packet_count = @truncate((transfer.size + mps - 1) / mps);

    // if (transfer.packet_count == 0) {
    //     transfer.packet_count = 1;
    // }

    req.attempted_size = transfer.size;
    req.attempted_bytes_remaining = transfer.size;
    req.attempted_packets_remaining = transfer.packet_count;

    active_transfer[id] = req;

    log.debug(@src(), "Setting up transactions on channel {d}:\n" ++
        "\t\tdma_addr=0x{x:0>8}, " ++
        "max_packet_size={d}, " ++
        "endpoint_number={d}, endpoint_direction={d},\n" ++
        "\t\tlow_speed={d}, endpoint_type={d}, device_address={d},\n\t\t" ++
        "size={d}, packet_count={d}, packet_id={d}, split_enable={d}, complete_split={}", .{
        id,
        registers.channel_dma_addr,
        characteristics.max_packet_size,
        characteristics.endpoint_number,
        characteristics.endpoint_direction,
        characteristics.low_speed_device,
        characteristics.endpoint_type,
        characteristics.device_address,
        transfer.size,
        transfer.packet_count,
        transfer.packet_id,
        split_control.split_enable,
        req.complete_split,
    });

    registers.channel_character = characteristics;
    registers.split_control = split_control;
    registers.transfer = transfer;

    // enable the channel
    channelStartTransaction(id, req);
}

// requires the following registers were already configured:
// - channel characteristics
// - transfer size
// - dma address
pub fn channelStartTransaction(id: ChannelId, req: *TransferRequest) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    const registers = channel_registers[id];

    // Clear pending interrupts
    registers.channel_int_mask = @bitCast(@as(u32, 0));
    registers.channel_int = @bitCast(@as(u32, 0xffff_ffff));

    // is this the completion part of a split transaction?
    var split_control = registers.split_control;
    split_control.complete_split = if (req.complete_split) 1 else 0;
    registers.split_control = split_control;

    // set odd frame and enable
    const next_frame = (host.frame_num.number & 0xffff) + 1;

    if (split_control.complete_split == 0) {
        req.csplit_retries = 0;
    }

    registers.channel_int_mask = .{ .halt = 1 };
    host.all_channel_interrupts_mask |= @as(u32, 1) << id;

    var channel_char = registers.channel_character;
    channel_char.odd_frame = @truncate(next_frame & 1);
    channel_char.enable = 1;
    //    channel_char.disable = 0;
    registers.channel_character = channel_char;

    log.debug(@src(), "channel {d} characteristics {x:0>8}", .{ id, @as(u32, @bitCast(registers.channel_character)) });
}

// ----------------------------------------------------------------------
// Deferred transfer support
// ----------------------------------------------------------------------

const DeferredTransferArgs = struct {
    req: *TransferRequest,
};

pub fn deferTransfer(req: *TransferRequest) !void {
    debugLogTransfer(req, "deferring");

    // first time through, allocate a semaphore
    // if the request is deferred more than once, the semaphore is reused
    if (req.deferrer_thread_sem == null) {
        req.deferrer_thread_sem = try semaphore.create(0);
        errdefer {
            semaphore.free(req.deferrer_thread_sem.?);
            req.deferrer_thread_sem = null;
        }
        log.debug(@src(), "created semaphore {d} for deferred transfer", .{req.deferrer_thread_sem.?});
    }

    // first time through, allocate a thread.
    // if the request is deferred more than once, the thread is reused
    if (req.deferrer_thread == null) {
        var args: DeferredTransferArgs = .{
            .req = req,
        };
        req.deferrer_thread = try schedule.spawn(deferredTransfer, "dwc defer", &args);
        log.debug(@src(), "spawned thread {d} for deferred transfer", .{req.deferrer_thread.?});
    }

    // let the thread progress
    semaphore.signal(req.deferrer_thread_sem.?) catch {};
}

fn deferredTransfer(args_ptr: *anyopaque) void {
    const args: *DeferredTransferArgs = @ptrCast(@alignCast(args_ptr));
    const req = args.req;

    var interval_ms: u32 = 0;

    var dev = req.device orelse return;
    var ep = req.endpoint_desc orelse return;

    if (dev.speed == UsbSpeed.High) {
        interval_ms = (@as(u32, 1) << @as(u5, @truncate(ep.interval)) - 1) /
            USB_UFRAMES_PER_MS;
    } else {
        interval_ms = ep.interval / USB_FRAMES_PER_MS;
    }

    // temporary while testing
    //    interval_ms = 2500;

    if (interval_ms == 0) {
        interval_ms = 1;
    }

    while (true) {
        semaphore.wait(req.deferrer_thread_sem.?) catch |err| {
            log.err(@src(), "deferredTransfer semaphore {d} error {any}", .{ req.deferrer_thread_sem.?, err });
            // TODO something
        };

        log.debug(@src(), "deferring transfer for {d}ms", .{interval_ms});

        schedule.sleep(interval_ms) catch |err| {
            log.err(@src(), "deferredTransfer sleep error {any}", .{err});
            // TODO something
        };

        if (channelAllocate()) |chid| {
            channelStartTransfer(chid, req);
        } else |err| {
            log.err(@src(), "channel allocate error: {any}", .{err});
        }
    }
}

fn debugLogTransfer(req: *TransferRequest, msg: []const u8) void {
    var transfer_type: []const u8 = "control";
    var endpoint_number: u8 = 0;

    if (req.endpoint_desc) |ep| {
        endpoint_number = ep.endpoint_address;
        switch (ep.getType()) {
            0b00 => transfer_type = "control",
            0b01 => transfer_type = "isochronous",
            0b10 => transfer_type = "bulk",
            0b11 => transfer_type = "interrupt",
        }
    }

    log.debug(@src(), "[{d}:{d} {s}] {s}", .{ req.device.?.address, endpoint_number, transfer_type, msg });
}

// ----------------------------------------------------------------------
// Main driver thread
// ----------------------------------------------------------------------

fn signalShutdown() void {
    shutdown_signal.signal();
}

fn isShuttingDown() bool {
    return shutdown_signal.isSignalled();
}

fn nextRequest() ?*TransferRequest {
    var req = transfer_mailbox.receive() catch |err| {
        log.err(@src(), "transfer_mailbox receive error: {any}", .{err});
        return null;
    };
    if (req.device == null) {
        log.err(@src(), "malformed xfer, no device given.", .{});
        return null;
    }
    return req;
}

fn channelForRequest(req: *TransferRequest) ?ChannelId {
    return channelAllocate() catch |err| {
        log.err(@src(), "channel allocate error: {any}", .{err});
        req.complete(TransferRequest.CompletionStatus.failed);
        return null;
    };
}

/// Driver thread proc
pub fn dwcDriverLoop(_: *anyopaque) void {
    while (!isShuttingDown()) {
        var xfer = nextRequest() orelse continue;
        var dev = xfer.device orelse continue;

        if (dev.isRootHub()) {
            root_hub.hubHandleTransfer(xfer);
        } else {
            var channel = channelForRequest(xfer) orelse continue;
            channelStartTransfer(channel, xfer);
        }
    }
}

// ----------------------------------------------------------------------
// scratch area - integrate this into the 'channel handling' section later
// ----------------------------------------------------------------------
const InterruptReason = enum {
    transfer_failed,
    transfer_needs_restart,
    transaction_needs_restart,
    transfer_needs_defer,
    transfer_completed,
};

fn channelInterrupt(id: ChannelId) void {
    const req: *TransferRequest = active_transfer[id] orelse {
        log.debug(@src(), "channel {d} received a spurious interrupt.", .{id});
        return;
    };

    const registers = channel_registers[id];
    const int_status: ChannelInterrupt = registers.channel_int;
    var interrupt_reason: InterruptReason = undefined;

    var buf = std.mem.zeroes([128]u8);
    const l = int_status.debugDecode(&buf);
    log.debug(@src(), "channel {d} interrupt{s}, characteristics 0x{x:0>8}, transfer 0x{x:0>8}, dma_addr 0x{x:0>8}", .{
        id,
        buf[0..l],
        @as(u32, @bitCast(registers.channel_character)),
        @as(u32, @bitCast(registers.transfer)),
        registers.channel_dma_addr,
    });

    if (int_status.stall == 1 or int_status.ahb_error == 1 or int_status.transaction_error == 1 or
        int_status.babble_error == 1 or int_status.excessive_transmission == 1 or
        int_status.frame_list_rollover == 1 or
        (int_status.nyet == 1 and !req.complete_split) or
        (int_status.data_toggle_error == 1 and registers.channel_character.endpoint_direction == usb.USB_ENDPOINT_DIRECTION_OUT))
    {
        log.err(@src(), "channel {d} transfer error (interrupts = 0x{x:0>8},  packet count = {d})", .{ id, @as(u32, @bitCast(int_status)), registers.transfer.packet_count });

        dumpStatus();
        channelStatus(id);

        interrupt_reason = .transfer_failed;
    } else if (int_status.frame_overrun == 1) {
        // log.debug(@src(),"channel {d} frame overrun. restarting transaction", .{id});
        interrupt_reason = .transaction_needs_restart;
    } else if (int_status.nyet == 1) {
        // log.debug(@src(),"channel {d} received nyet from device; split retry needed", .{id});
        req.csplit_retries += 1;
        if (req.csplit_retries > 10) {
            // log.debug(@src(),"channel {d} restarting split transaction (CSPLIT tried {d} times)", .{ id, req.csplit_retries });
            req.complete_split = false;
        }
        interrupt_reason = .transaction_needs_restart;
    } else if (int_status.nak == 1) {
        // log.debug(@src(),"channel {d} received nak from
        // device; deferring transfer", .{id});
        req.nak_count += 1;

        if (req.nak_count > 5) {
            // temporary while testing
            interrupt_reason = .transfer_failed;
        } else {
            interrupt_reason = .transfer_needs_defer;
            req.complete_split = false;
        }
    } else {
        interrupt_reason = channelHaltedNormal(id, req, int_status);
    }

    log.debug(@src(), "channel {d} interrupt_reason {s}", .{ id, @tagName(interrupt_reason) });

    var completion: TransferRequest.CompletionStatus = undefined;

    switch (interrupt_reason) {
        .transfer_completed => completion = .ok,
        .transfer_failed => completion = .failed,
        .transfer_needs_defer => {},
        .transfer_needs_restart => {
            channelStartTransfer(id, req);
            return;
        },
        .transaction_needs_restart => {
            channelStartTransaction(id, req);
            return;
        },
    }

    // transfer either finished, encountered an error, or needs to be
    // retried later.

    // This is some odd cleanup... we're telling the host to
    // deallocate this channel. (We don't want to keep the channel reserved
    // while deferring a retry. Some other transfer might need the channel.)
    req.next_data_pid = registers.transfer.packet_id;

    registers.channel_int_mask = @bitCast(@as(u32, 0));
    registers.channel_int = @bitCast(@as(u32, 0xffff_ffff));

    active_transfer[id] = null;
    channelFree(id);

    if (!req.isControlRequest() or req.control_phase == TransferRequest.control_data_phase) {
        req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
    }

    if (interrupt_reason == .transfer_needs_defer) {
        if (deferTransfer(req)) {
            return;
        } else |_| {
            completion = .failed;
        }
    }

    req.complete(completion);
}

fn channelHaltedNormal(id: ChannelId, req: *TransferRequest, ints: ChannelInterrupt) InterruptReason {
    const registers = channel_registers[id];
    const packets_remaining = registers.transfer.packet_count;
    const packets_transferred = req.attempted_packets_remaining - packets_remaining;
    const bytes_remaining = registers.transfer.size;
    _ = bytes_remaining;

    // log.debug(@src(),"channel {d} reports packets_remaining {d}", .{ id, packets_remaining });
    // log.debug(@src(),"channel {d} packets remaining {d} of {d}, so packets transferred {d}", .{ id, packets_remaining, req.attempted_packets_remaining, packets_transferred });

    if (packets_transferred != 0) {
        var bytes_transferred: TransferBytes = 0;
        const char = registers.channel_character;
        const max_packet_size = char.max_packet_size;
        const dir = char.endpoint_direction;
        const ty = char.endpoint_type;

        if (dir == usb.USB_ENDPOINT_DIRECTION_IN) {
            if (registers.transfer.size > req.attempted_bytes_remaining) {
                log.err(@src(), "Transfer size seems wrong 0x{x} (attempted was 0x{x})", .{ registers.transfer.size, req.attempted_bytes_remaining });

                // High bit is set, do we have a negative number?
                log.sliceDump(@src(), &channel_buffers[id]);

                bytes_transferred = req.attempted_bytes_remaining;
            } else {
                bytes_transferred = req.attempted_bytes_remaining - registers.transfer.size;
            }

            if (bytes_transferred > 0 and req.cur_data_ptr != null and !isAligned(req.cur_data_ptr.?)) {
                // we're reading into a different buffer than the
                // original caller provided. copy the results from our
                // DMA aligned buffer to the one the caller can see
                const start_pos = req.attempted_size - req.attempted_bytes_remaining;
                @memcpy(req.cur_data_ptr.?, channel_buffers[id][start_pos .. start_pos + bytes_transferred]);
            }
        } else {
            // hardware doesn't properly update transfer registers'
            // size field for OUT transfers
            if (packets_transferred > 1) {
                bytes_transferred += max_packet_size * (packets_transferred - 1);
            }

            if (packets_remaining == 0 and
                (req.attempted_size % max_packet_size != 0 or req.attempted_size == 0))
            {
                bytes_transferred += req.attempted_size % max_packet_size;
            } else {
                bytes_transferred += max_packet_size;
            }
        }

        // log.debug(@src(),"channel {d} calculated {d} bytes transferred", .{ self.id, bytes_transferred });

        req.attempted_packets_remaining -= packets_transferred;
        req.attempted_bytes_remaining -= bytes_transferred;

        if (req.cur_data_ptr != null) {
            req.cur_data_ptr.? += bytes_transferred;
        }

        //        log.debug(@src(),"channel {d} packets remaining {d}, bytes remaining {d}", .{ id, req.attempted_packets_remaining, req.attempted_bytes_remaining });

        // is the transfer completed?
        if (req.attempted_packets_remaining == 0 or
            (dir == usb.USB_ENDPOINT_DIRECTION_IN and
            bytes_transferred < packets_transferred * max_packet_size))
        {
            if (ints.transfer_complete == 0) {
                log.err(@src(), "channel {d} expected transfer_completed flag but was not observed.", .{id});
                return .transfer_failed;
            }

            if (req.short_attempt and
                req.attempted_bytes_remaining == 0 and
                ty != TransferType.interrupt)
            {
                log.debug(@src(), "channel {d} starting next part of {d} byte transfer, after short attempt of {d} bytes", .{ id, req.size, req.attempted_size });
                req.complete_split = false;
                req.next_data_pid = registers.transfer.packet_id;
                if (!req.isControlRequest() or
                    req.control_phase == TransferRequest.control_data_phase)
                {
                    req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
                }
                return .transfer_needs_restart;
            }

            if (req.isControlRequest() and req.control_phase < 2) {
                req.complete_split = false;
                if (req.control_phase == TransferRequest.control_data_phase) {
                    req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
                }

                req.control_phase += 1;

                if (req.control_phase == TransferRequest.control_data_phase and req.size == 0) {
                    req.control_phase += 1;
                }
                return .transfer_needs_restart;
            }

            log.debug(@src(), "channel {d} transfer completed", .{id});
            return .transfer_completed;
        } else {
            // transfer not complete, start the next transaction
            if (registers.split_control.split_enable == 1) {
                req.complete_split = !req.complete_split;
            }

            log.debug(@src(), "channel {d} will continue transfer", .{id});
            return .transaction_needs_restart;
        }
    } else {
        // no packets transferred. also not an error. indicates that
        // the start_split packet was acknowledged.
        if (ints.ack == 1 and
            registers.split_control.split_enable == 1 and
            !req.complete_split)
        {
            // Start CSPLIT
            req.complete_split = true;
            log.debug(@src(), "channel {d} must continue transfer (complete_split = {})", .{ id, req.complete_split });
            schedule.sleep(50) catch |err| {
                log.err(@src(), "Can't sleep, clown'll eat me. {any}", .{err});
            };
            return .transaction_needs_restart;
        } else if (req.isControlRequest() and req.control_phase == TransferRequest.control_status_phase) {
            log.debug(@src(), "channel {d} status phase completed", .{id});
            return .transfer_completed;
        } else {
            log.err(@src(), "channel {d} no packets transferred", .{id});
            return .transfer_failed;
        }
    }
}
