const std = @import("std");
const Allocator = std.mem.Allocator;

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
const Forth = @import("../forty/forth.zig");
const Logger = @import("../logger.zig");
pub var log: *Logger = undefined;

const schedule = @import("../schedule.zig");
const semaphore = @import("../semaphore.zig");
const synchronize = @import("../synchronize.zig");
const time = @import("../time.zig");
const usb = @import("../usb.zig");

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
    InvalidRequest,
    InvalidResponse,
    DataLengthMismatch,
    NotConnected,
    NoAvailableChannel,
    Busy,
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
pub const DMA_ALIGNMENT: usize = 16;

const empty_slice: []u8 = &[_]u8{};

const register_base: u64 = root.HAL.peripheral_base + 0x980_000;
const core: *volatile CoreRegisters = @ptrFromInt(register_base);
const host: *volatile HostRegisters = @ptrFromInt(register_base + 0x400);
const channel_base: u64 = register_base + 0x500;
const power: *volatile PowerAndClock = @ptrFromInt(register_base + 0xe00);
var power_controller: *PowerController = undefined;

var driver_thread: schedule.TID = schedule.NO_TID;
var shutdown_signal: synchronize.OneShot = .{};

var root_hub: RootHub = .{};
pub const root_hub_hub_descriptor = RootHub.root_hub_hub_descriptor_base;
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

    for (0..dwc_max_channels) |i| {
        const chid: ChannelId = @intCast(i);
        channel_pool[chid] = try Channel.init(chid);
    }

    power_controller = power_ctrl;

    root_hub.init(host);

    interrupt_controller = intc;
    irq_id = ii;

    return self;
}

pub fn initialize(self: *Self) !void {
    _ = self;

    try powerOn();
    try verifyHostControllerDevice();

    core.ahb_config.global_interrupt_enable = 0;

    coreInit();
    try coreReset();
    setHostMode();

    time.delayMillis(50);

    power.* = @bitCast(@as(u32, 0));

    num_host_channels = core.hardware_config_2.num_host_channels;

    log.debug(@src(), "power on host port", .{});

    var prt = host.port;
    prt.power = 1;
    prt.enabled = 0; // these are W1C
    prt.enabled_changed = 0;
    prt.connected_changed = 0;
    prt.overcurrent_changed = 0;
    host.port = prt;

    time.delayMillis(200);

    host.config.fs_ls_support_only = 0;

    for (0..dwc_max_channels) |chid| {
        channel_registers[chid].channel_int = @bitCast(@as(u32, 0xffff_ffff));
        channel_registers[chid].channel_int_mask = @bitCast(@as(u32, 0));
    }

    log.debug(@src(), "clear interrupts", .{});

    core.core_interrupt_mask = @bitCast(@as(u32, 0));
    core.core_interrupt_status = @bitCast(@as(u32, 0xffff_ffff));

    const rx_words: u32 = 1024; // Size of Rx FIFO in 4-byte words
    const tx_words: u32 = 1024; // Size of Non-periodic Tx FIFO in 4-byte words
    const ptx_words: u32 = 1024; // Size of Periodic Tx FIFO in 4-byte words

    log.debug(@src(), "configure and flush fifos", .{});

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
    ahb.max_axi_burst = 0x3;
    core.ahb_config = ahb;

    log.debug(@src(), "enable interrupts", .{});

    // Connect interrupt handler & enable interrupts on the ARM PE
    interrupt_controller.connect(irq_id, &irq_handler, null);
    interrupt_controller.enable(irq_id);

    var enable_ints: InterruptMask = core.core_interrupt_mask;
    enable_ints.port = 1;
    enable_ints.host_channel = 1;
    core.core_interrupt_mask = enable_ints;

    core.ahb_config.global_interrupt_enable = 1;
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

    log.debug(@src(), "Core registers at 0x{x:0>8}", .{@intFromPtr(core)});
    log.debug(@src(), "DWC2 OTG core rev: {x}.{x:0>3}", .{ id.device_series, id.device_minor_rev });

    if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
        log.warn(@src(), " gsnpsid = 0x{x:0>8}, vendor = 0x{x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
        return error.IncorrectDevice;
    }

    const hwcfg = core.hardware_config_2;
    const fs_phy_type = hwcfg.full_speed_physical_type;
    const hs_phy_type = hwcfg.high_speed_physical_type;
    const dma_support = hwcfg.dma_architecture;
    const num_channels = hwcfg.num_host_channels;

    log.debug(@src(), "operating mode: {s}", .{
        @tagName(hwcfg.operating_mode),
    });

    log.debug(@src(), "hsphy type: {s}, fsphy type: {s}, dma support: {s}", .{
        @tagName(hs_phy_type),
        @tagName(fs_phy_type),
        @tagName(dma_support),
    });

    log.debug(@src(), "channels: {d}", .{
        num_channels,
    });
}

fn coreInit() void {
    log.debug(@src(), "core init", .{});
    var usbcfg = core.usb_config;
    usbcfg.term_sel_dl_pulse = 0;
    usbcfg.ulpi_fsls = 0;
    usbcfg.phy_sel = 0;
    usbcfg.ulpi_ext_vbus_drv = 0;
    usbcfg.ulpi_ext_vbus_indicator = 0;
    core.usb_config = usbcfg;
}

fn setHostMode() void {
    log.debug(@src(), "set host mode", .{});
    var usbcfg = core.usb_config;
    usbcfg.force_host_mode = 1;
    usbcfg.force_device_mode = 0;
    core.usb_config = usbcfg;
}

fn coreReset() !void {
    log.debug(@src(), "core reset", .{});

    // trigger the soft reset
    core.reset.soft_reset = 1;

    // wait up to 10 ms for reset to finish
    const reset_end = time.deadlineMillis(10);

    while (time.ticks() < reset_end and core.reset.soft_reset != 0) {}

    if (core.reset.soft_reset != 0) {
        log.warn(@src(), "soft reset complete not observed before timeout", .{});
        return Error.InitializationFailure;
    }

    // wait for AHB master to go idle
    const ahb_idle_wait_end = time.deadlineMillis(10);

    while (time.ticks() < ahb_idle_wait_end and core.reset.ahb_master_idle == 0) {}

    if (core.reset.ahb_master_idle != 1) {
        log.warn(@src(), "ahb master idle not observed before timeout", .{});
        return Error.InitializationFailure;
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

    if (core.reset.tx_fifo_flush == 1) {
        return error.InitializationFailure;
    }
}

fn rxFifoFlush() !void {
    const flush: Reset = .{
        .rx_fifo_flush = 1,
    };
    core.reset = flush;
    const flush_wait_end = time.deadlineMillis(100);
    while (core.reset.rx_fifo_flush == 1 and time.ticks() < flush_wait_end) {}

    if (core.reset.rx_fifo_flush == 1) {
        return error.InitializationFailure;
    }
}

fn hostPortSpeed() u8 {
    const hprt = host.port;

    return switch (hprt.speed) {
        .high => usb.USB_SPEED_HIGH,
        .full => usb.USB_SPEED_FULL,
        .low => usb.USB_SPEED_LOW,
        .undefined => usb.USB_SPEED_UNKNOWN,
    };
}

// ----------------------------------------------------------------------
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(_: *InterruptController, _: IrqId, _: ?*anyopaque) void {
    const gint_status = core.core_interrupt_status;
    const gint_mask = core.core_interrupt_mask;

    // check for spurious interrupt, not interested
    const ints = @as(u32, @bitCast(gint_status)) & @as(u32, @bitCast(gint_mask));
    if (ints == 0) {
        log.debug(@src(), "irq handle: spurious interrupt 0x{x:0>8}", .{@as(u32, @bitCast(gint_status))});
        return;
    }

    // check for port interrupt
    if (gint_status.port != 0) {
        log.debug(@src(), "irq handle: host port interrupt, port status 0x{x:0>8}", .{@as(u32, @bitCast(host.port))});
        root_hub.hubHandlePortInterrupt();
    }

    // check for some channel interrupted
    if (gint_status.host_channel != 0) {
        const all_intrs = host.all_channel_interrupts;

        log.debug(@src(), "irq handle: host channel ints 0x{x:0>8}", .{@as(u32, @bitCast(all_intrs))});

        // Find the channel that has something to say
        var channel_mask: u32 = 1;
        // TODO consider using @ctz to find the lowest bit that's set,
        // instead of looping over all 16 channels.
        for (0..dwc_max_channels) |i| {
            const chid: ChannelId = @truncate(i);
            if ((all_intrs & channel_mask) != 0) {
                if (channel_registers[chid].channel_character.endpoint_direction == 1) {
                    channelHandleInInterrupt(chid);
                } else {
                    channelHandleOutInterrupt(chid);
                }
            }
            channel_mask <<= 1;
        }
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
const ControlTransferState = enum {
    NotControl,
    Setup,
    DataIn,
    DataOut,
    StatusIn,
    StatusOut,
};

const Channel = struct {
    ep0_state: ControlTransferState,
    packet_count: usb.TransferPackets,
    transfer_length: usb.TransferBytes,
    chid: ChannelId,
    busy: bool,
    waitsem: semaphore.SID,
    urb: ?*usb.URB,

    fn init(chid: ChannelId) !Channel {
        return .{
            .ep0_state = .NotControl,
            .packet_count = 0,
            .transfer_length = 0,
            .chid = chid,
            .busy = false,
            .waitsem = try semaphore.create(0),
            .urb = null,
        };
    }
};

var channel_assignments: synchronize.AllocationSet("dwc_otg_usb channels", u5, dwc_max_channels) = .{};
var channel_buffers: [dwc_max_channels][1024]u8 align(DMA_ALIGNMENT) = [_][1024]u8{.{0} ** 1024} ** dwc_max_channels;
var channel_pool: [dwc_max_channels]Channel = undefined;

const ChannelId = u5;

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

fn channelAllocate() error{NoAvailableChannel}!ChannelId {
    const chid = try channel_assignments.allocate();
    errdefer channel_assignments.free(chid);

    if (chid >= num_host_channels) {
        return error.NoAvailableChannel;
    }

    return chid;
}

pub fn channelFree(channel: ChannelId) void {
    channel_pool[channel].urb = null;
    channel_pool[channel].busy = false;

    host.all_channel_interrupts_mask &= ~(@as(u32, 1) << channel);

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

fn calculatePacketCount(input_size_in: usb.TransferBytes, mps: usb.PacketSize, size_out: *usb.TransferBytes) usb.TransferPackets {
    const input_size = input_size_in;
    var num_packets: u32 = (input_size + mps - 1) / mps;

    if (num_packets > 256) {
        num_packets = 256;
    }

    if (input_size == 0) {
        num_packets = 1;
    }

    size_out.* = input_size;
    return @truncate(num_packets);
}

// ----------------------------------------------------------------------
// New Style Interrupt Handling
// ----------------------------------------------------------------------
fn channelHandleInInterrupt(chid: ChannelId) void {
    const chan = &channel_pool[chid];
    const chreg = channel_registers[chid];
    const chints = chreg.channel_int;
    const urb = chan.urb orelse return;

    log.debug(@src(), "ch {d} in interrupt status 0x{x:0>8}", .{ chid, @as(u32, @bitCast(chints)) });
    chreg.channel_int = chints;

    if (chints.halt != 0) {
        if (chints.transfer_complete != 0) {
            log.debug(@src(), "ch {d} in interrupt, halted, xfrc", .{chid});
            urb.status = .OK;
            const count = chan.transfer_length - chreg.transfer.size;
            // const used_packets = chan.packet_count - chreg.transfer.packet_count;
            // _ = used_packets;

            urb.actual_length += count;

            const data_toggle = chreg.transfer.packet_id;
            if (data_toggle == DwcTransferSizePid.data0) {
                urb.data_toggle = 0;
            } else {
                urb.data_toggle = 1;
            }

            // TODO - does this work if we need multiple datain packets?
            if (urb.ep.isType(usb.USB_ENDPOINT_TYPE_CONTROL)) {
                // note that not all ep0_states are reachable on an
                // "in" interrupt.
                if (chan.ep0_state == .DataIn) {
                    chan.ep0_state = .StatusOut;
                    controlUrbInit(chan, urb, urb.setup.?, urb.transfer_buffer, urb.transfer_buffer_length);
                } else if (chan.ep0_state == .StatusIn) {
                    chan.ep0_state = .Setup;
                    urbWaitup(urb);
                }
            } else if (urb.ep.isType(usb.USB_ENDPOINT_TYPE_ISOCHRONOUS)) {
                //
            } else {
                urbWaitup(urb);
            }
        } else if (chints.ahb_error != 0) {
            log.debug(@src(), "ch {d} in interrupt, ahb_error", .{chid});
            urbFail(urb, .IO);
        } else if (chints.stall != 0) {
            log.debug(@src(), "ch {d} in interrupt, stall", .{chid});
            urbFail(urb, .Stall);
        } else if (chints.nak != 0) {
            log.debug(@src(), "ch {d} in interrupt, nak", .{chid});
            urbFail(urb, .Nak);
        } else if (chints.nyet != 0) {
            log.debug(@src(), "ch {d} in interrupt, nyet", .{chid});
            urbFail(urb, .Nyet);
        } else if (chints.transaction_error != 0) {
            log.debug(@src(), "ch {d} in interrupt, transaction_error", .{chid});
            urbFail(urb, .IO);
        } else if (chints.babble_error != 0) {
            log.debug(@src(), "ch {d} in interrupt, babble_error", .{chid});
            urbFail(urb, .Babble);
        } else if (chints.data_toggle_error != 0) {
            log.debug(@src(), "ch {d} in interrupt, data_toggle_error", .{chid});
            urbFail(urb, .DataToggle);
        } else if (chints.frame_overrun != 0) {
            log.debug(@src(), "ch {d} in interrupt, frame_overrun", .{chid});
            urbFail(urb, .IO);
        }
    }
}

fn channelHandleOutInterrupt(chid: ChannelId) void {
    const chan = &channel_pool[chid];
    const chreg = channel_registers[chid];
    const chints = chreg.channel_int;
    const urb = chan.urb orelse return;

    log.debug(@src(), "ch {d} out interrupt status 0x{x:0>8}", .{ chid, @as(u32, @bitCast(chints)) });
    chreg.channel_int = chints;

    if (chints.halt != 0) {
        if (chints.transfer_complete != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, xfrc", .{chid});
            urb.status = .OK;
            const count = chreg.transfer.size;
            const used_packets = if (chan.transfer_length == 0) 1 else (chan.packet_count - chreg.transfer.packet_count);

            urb.actual_length += (used_packets - 1) * urb.ep.getMaxPacketSize() + count;

            const data_toggle = chreg.transfer.packet_id;
            if (data_toggle == DwcTransferSizePid.data0) {
                urb.data_toggle = 0;
            } else {
                urb.data_toggle = 1;
            }

            if (urb.ep.isType(usb.USB_ENDPOINT_TYPE_CONTROL)) {
                if (chan.ep0_state == .Setup) {
                    if (urb.setup.?.data_size > 0) {
                        if ((urb.setup.?.request_type & 0x80) != 0) {
                            chan.ep0_state = .DataIn;
                        } else {
                            chan.ep0_state = .DataOut;
                        }
                    } else {
                        chan.ep0_state = .StatusIn;
                    }
                    controlUrbInit(chan, urb, urb.setup.?, urb.transfer_buffer, urb.transfer_buffer_length);
                } else if (chan.ep0_state == .DataOut) {
                    chan.ep0_state = .StatusIn;
                    controlUrbInit(chan, urb, urb.setup.?, urb.transfer_buffer, urb.transfer_buffer_length);
                } else if (chan.ep0_state == .StatusOut) {
                    chan.ep0_state = .Setup;
                    urbWaitup(urb);
                }
            } else if (urb.ep.isType(usb.USB_ENDPOINT_TYPE_ISOCHRONOUS)) {
                //
            } else {
                urbWaitup(urb);
            }
        } else if (chints.ahb_error != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, ahb_error", .{chid});
            urbFail(urb, .IO);
        } else if (chints.stall != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, stall", .{chid});
            urbFail(urb, .Stall);
        } else if (chints.nak != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, nak", .{chid});
            urbFail(urb, .Nak);
        } else if (chints.nyet != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, nyet", .{chid});
            urbFail(urb, .Nyet);
        } else if (chints.transaction_error != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, transaction_error", .{chid});
            urbFail(urb, .IO);
        } else if (chints.babble_error != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, babble_error", .{chid});
            urbFail(urb, .Babble);
        } else if (chints.data_toggle_error != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, data_toggle_error", .{chid});
            urbFail(urb, .DataToggle);
        } else if (chints.frame_overrun != 0) {
            log.debug(@src(), "ch {d} out interrupt, halted, frame_overrun", .{chid});
            urbFail(urb, .IO);
        }
    }
}

fn urbWaitup(urb: *usb.URB) void {
    const chan: *Channel = @alignCast(@ptrCast(urb.private orelse return));

    if (urb.isSynchronous()) {
        semaphore.signal(chan.waitsem) catch {
            // TODO what do?
            // could happen if the thread is killed while waiting?
        };
    } else {
        chan.urb = null;
        urb.private = null;
        channelFree(chan.chid);
        urb.callCompletion();
    }
}

fn urbFail(urb: *usb.URB, detail: usb.URB.StatusDetail) void {
    urb.status = .Failed;
    urb.status_detail = detail;
    urbWaitup(urb);
}

// ----------------------------------------------------------------------
// Transfer Handling
// ----------------------------------------------------------------------

pub fn rootHubControl(setup: *usb.SetupPacket, data: ?[]u8) usb.URB.Status {
    return root_hub.control(setup, data);
}

pub fn submitUrb(urb: *usb.URB) Error!usb.URB.Status {
    if (urb.setup != null and !isAligned(@ptrCast(urb.setup.?))) {
        log.debug(@src(), "setup buffer misaligned", .{});
        return Error.InvalidRequest;
    }

    if (urb.transfer_buffer != null and !isAligned(urb.transfer_buffer.?)) {
        log.debug(@src(), "transfer buffer misaligned (ptr 0x{x:0>8})", .{&urb.transfer_buffer.?[0]});
        return Error.InvalidRequest;
    }

    if (!urb.port.connected) {
        return Error.NotConnected;
    }

    const flags = cpu.disable();
    defer cpu.restore(flags);

    const chid = try channelAllocate();

    const chan = &channel_pool[chid];
    chan.urb = urb;

    urb.private = chan;
    urb.actual_length = 0;
    urb.status = .Busy;
    urb.status_detail = .OK;

    switch (urb.ep.getType()) {
        usb.USB_ENDPOINT_TYPE_CONTROL => {
            chan.ep0_state = .Setup;
            controlUrbInit(chan, urb, urb.setup.?, urb.transfer_buffer, urb.transfer_buffer_length);
        },
        usb.USB_ENDPOINT_TYPE_BULK, usb.USB_ENDPOINT_TYPE_INTERRUPT => {
            bulkOrInterruptUrbInit(chan, urb, urb.transfer_buffer, urb.transfer_buffer_length);
        },
        usb.USB_ENDPOINT_TYPE_ISOCHRONOUS => {},
    }

    if (urb.isSynchronous()) {
        // TODO: support timeouts. Requires changes to scheduler. Today a
        // thread cannot be in the sleepq and the semaphore queue simultaneously
        semaphore.wait(chan.waitsem) catch {
            urb.status = .Failed;
        };

        urb.private = null;
        channelFree(chid);
    }

    return urb.status;
}

fn controlUrbInit(
    chan: *Channel,
    urb: *usb.URB,
    setup: *usb.SetupPacket,
    transfer_buffer: ?[*]u8,
    transfer_buffer_length: usb.TransferBytes,
) void {
    _ = transfer_buffer_length;

    const ep_mps = urb.ep.getMaxPacketSize();

    switch (chan.ep0_state) {
        .Setup => {
            chan.packet_count = calculatePacketCount(8, ep_mps, &chan.transfer_length);
            channelInit(chan, urb.port.device_address, 0x00, usb.USB_ENDPOINT_TYPE_CONTROL, ep_mps, urb.port.speed);
            channelTransfer(chan, 0x00, std.mem.asBytes(setup), chan.transfer_length, chan.packet_count, DwcTransferSizePid.setup);
        },
        .DataIn => {
            chan.packet_count = calculatePacketCount(setup.data_size, ep_mps, &chan.transfer_length);
            channelInit(chan, urb.port.device_address, 0x80, usb.USB_ENDPOINT_TYPE_CONTROL, ep_mps, urb.port.speed);
            channelTransfer(chan, 0x80, transfer_buffer, chan.transfer_length, chan.packet_count, DwcTransferSizePid.data1);
        },
        .DataOut => {
            chan.packet_count = calculatePacketCount(setup.data_size, ep_mps, &chan.transfer_length);
            channelInit(chan, urb.port.device_address, 0x00, usb.USB_ENDPOINT_TYPE_CONTROL, ep_mps, urb.port.speed);
            channelTransfer(chan, 0x00, transfer_buffer, chan.transfer_length, chan.packet_count, DwcTransferSizePid.data1);
        },
        .StatusIn => {
            chan.packet_count = calculatePacketCount(0, ep_mps, &chan.transfer_length);
            channelInit(chan, urb.port.device_address, 0x80, usb.USB_ENDPOINT_TYPE_CONTROL, ep_mps, urb.port.speed);
            channelTransfer(chan, 0x80, null, chan.transfer_length, chan.packet_count, DwcTransferSizePid.data1);
        },
        .StatusOut => {
            chan.packet_count = calculatePacketCount(0, ep_mps, &chan.transfer_length);
            channelInit(chan, urb.port.device_address, 0x00, usb.USB_ENDPOINT_TYPE_CONTROL, ep_mps, urb.port.speed);
            channelTransfer(chan, 0x00, null, chan.transfer_length, chan.packet_count, DwcTransferSizePid.data1);
        },
        else => {},
    }
}

fn bulkOrInterruptUrbInit(
    chan: *Channel,
    urb: *usb.URB,
    transfer_buffer: ?[*]u8,
    transfer_buffer_length: usb.TransferBytes,
) void {
    const ep_mps = urb.ep.getMaxPacketSize();
    chan.packet_count = calculatePacketCount(transfer_buffer_length, ep_mps, &chan.transfer_length);

    const hc_pid = if (urb.data_toggle == 0) DwcTransferSizePid.data0 else DwcTransferSizePid.data1;

    channelInit(chan, urb.port.device_address, urb.ep.endpoint_address, urb.ep.getType(), ep_mps, urb.port.speed);
    channelTransfer(chan, urb.ep.endpoint_address, transfer_buffer, chan.transfer_length, chan.packet_count, hc_pid);
}

fn channelInit(
    chan: *Channel,
    device_address: usb.DeviceAddress,
    ep_address: u8,
    ep_type: u8,
    ep_mps: usb.PacketSize,
    speed: u8,
) void {
    var chreg = channel_registers[chan.chid];

    // Clear any old interrupts for this channel
    chreg.channel_int = @bitCast(@as(u32, 0xffff_ffff));

    // Set interrupt mask to enable halted interrupt
    var intmask: reg.ChannelInterrupt = .{
        .halt = 1,
    };

    // Interrupt URBs also need to know about NAKs
    if (ep_type == usb.USB_ENDPOINT_TYPE_INTERRUPT) {
        intmask.nak = 1;
    }

    chreg.channel_int_mask = intmask;

    // Enable host's channel interrupt for this channel
    host.all_channel_interrupts_mask |= @as(u32, 1) << chan.chid;

    channelCharacterInit(chan, device_address, ep_address, ep_type, ep_mps, speed);
}

fn channelCharacterInit(
    chan: *Channel,
    device_address: usb.DeviceAddress,
    ep_addr: u8,
    ep_type: u8,
    ep_mps: usb.PacketSize,
    speed: u8,
) void {
    var char: ChannelCharacteristics = .{
        .max_packet_size = ep_mps,
        .endpoint_number = @truncate(ep_addr & 0xf),
        .endpoint_type = @truncate(ep_type & 0x3),
        .device_address = device_address,
    };

    if ((ep_addr & 0x80) == 0x80) {
        char.endpoint_direction = 0b1;
    }

    if ((speed == usb.USB_SPEED_LOW) and (hostPortSpeed() != usb.USB_SPEED_LOW)) {
        char.low_speed_device = 0b1;
    }

    if (ep_type == usb.USB_ENDPOINT_TYPE_INTERRUPT) {
        char.odd_frame = 0b1;
    }

    log.debug(@src(), "ch {d} setting characteristics 0x{x:0>8}", .{ chan.chid, @as(u32, @bitCast(char)) });

    channel_registers[chan.chid].channel_character = char;
}

fn channelTransfer(
    chan: *Channel,
    ep_addr: u8,
    buffer: ?[*]u8,
    size: usb.TransferBytes,
    packet_count: usb.TransferPackets,
    hc_pid: u2,
) void {
    _ = ep_addr;

    const chreg = channel_registers[chan.chid];

    chreg.transfer = .{
        .size = size,
        .packet_count = packet_count,
        .packet_id = hc_pid,
        .do_ping = 0,
    };

    if (buffer) |b| {
        chreg.channel_dma_addr = @truncate(@intFromPtr(b) & 0xffff_ffff);
    } else {
        chreg.channel_dma_addr = 0;
    }

    const is_oddframe: u1 = if ((host.frame_num.number & 0b1) != 0) 0 else 1;
    chreg.channel_character.odd_frame = is_oddframe;

    log.debug(@src(), "ch {d} starting {d}x{d} transfer {s} 0x{x:0>8} to {d}:{d}", .{
        chan.chid,
        packet_count,
        size,
        if (chreg.channel_character.endpoint_direction == 1) "in" else "out",
        chreg.channel_dma_addr,
        chreg.channel_character.device_address,
        chreg.channel_character.endpoint_number,
    });

    var char = chreg.channel_character;
    char.enable = 1;
    char.disable = 0;
    chreg.channel_character = char;
}
