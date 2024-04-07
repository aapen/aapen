const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const PendingTransfers = DoublyLinkedList(*TransferRequest);

const log = std.log.scoped(.dwc_otg_usb);

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
const Bus = usb.Bus;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const Device = usb.Device;
const DeviceAddress = usb.DeviceAddress;
const DeviceConfiguration = usb.DeviceConfiguration;
const DeviceDescriptor = usb.DeviceDescriptor;
const EndpointDescriptor = usb.EndpointDescriptor;
const EndpointDirection = usb.EndpointDirection;
const EndpointNumber = usb.EndpointNumber;
const Hub = usb.Hub;
const InterfaceDescriptor = usb.InterfaceDescriptor;
const LangID = usb.LangID;
const PacketSize = usb.PacketSize;
const PID = usb.PID2;
const RequestTypeDirection = usb.RequestTypeDirection;
const RequestTypeRecipient = usb.RequestTypeRecipient;
const RequestTypeType = usb.RequestTypeType;
const SetupPacket = usb.SetupPacket;
const StringDescriptor = usb.StringDescriptor;
const StringIndex = usb.StringIndex;
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferFactory = usb.TransferFactory;
const TransferType = usb.TransferType;
const UsbSpeed = usb.UsbSpeed;
const USB_FRAMES_PER_MS = usb.FRAMES_PER_MS;
const USB_UFRAMES_PER_MS = usb.UFRAMES_PER_MS;

const reg = @import("dwc/registers.zig");
const Channel = @import("dwc/channel.zig");
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

// ----------------------------------------------------------------------
// HCD state
// ----------------------------------------------------------------------
pub const DEFAULT_TRANSFER_TIMEOUT = 1000;
pub const DEFAULT_INTERVAL = 1;
pub const DMA_ALIGNMENT: usize = 64;

const HcdChannels = ChannelSet.init("dwc_otg_usb channels", u5, dwc_max_channels);
const UsbTransferMailbox = Mailbox(*TransferRequest);

const empty_slice: []u8 = &[_]u8{};

allocator: Allocator,
core_registers: *volatile CoreRegisters,
host_registers: *volatile HostRegisters,
power_and_clock_control: *volatile PowerAndClock,
all_channel_intmask_lock: TicketLock,
intc: *InterruptController,
irq_id: IrqId,
irq_handler: IrqHandler = irqHandle,
translations: *const AddressTranslations,
power_controller: *PowerController,
num_host_channels: u4,
channel_assignments: HcdChannels = .{},
channels: [dwc_max_channels]Channel = [_]Channel{.{}} ** dwc_max_channels,
root_hub: RootHub = .{},
transfer_mailbox: UsbTransferMailbox,
driver_thread: schedule.TID,
shutdown_signal: OneShot = .{},

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------
pub fn defineModule(forth: *Forth) !void {
    try forth.defineNamespace(Self, .{
        .{ "dumpStatus", "usb-hci-status" },
        .{ "channelStatus", "usb-channel-status" },
    });
}

pub fn channelStatus(self: *Self, chid: u64) void {
    self.channels[chid].channelStatus();
}

// ----------------------------------------------------------------------
// Core interface layer: Initialization
// ----------------------------------------------------------------------
pub fn init(
    allocator: Allocator,
    register_base: u64,
    intc: *InterruptController,
    irq_id: IrqId,
    translations: *AddressTranslations,
    power: *PowerController,
) !*Self {
    const self = try allocator.create(Self);

    self.* = .{
        .allocator = allocator,
        .core_registers = @ptrFromInt(register_base),
        .host_registers = @ptrFromInt(register_base + 0x400),
        .power_and_clock_control = @ptrFromInt(register_base + 0xe00),
        .all_channel_intmask_lock = TicketLock.init("all channels interrupt mask", true),
        .intc = intc,
        .irq_id = irq_id,
        .translations = translations,
        .power_controller = power,
        .num_host_channels = 0,
        .transfer_mailbox = undefined,
        .driver_thread = schedule.NO_TID,
        .shutdown_signal = .{},
    };

    self.root_hub.init(self.host_registers);

    for (0..dwc_max_channels) |chid| {
        const register_offset: u64 = 0x500 + (@sizeOf(ChannelRegisters) * chid);
        const registers: u64 = register_base + register_offset;
        const aligned_buffer: []u8 = try allocator.alignedAlloc(u8, DMA_ALIGNMENT, 1024);
        self.channels[chid].init(self, @truncate(chid), @ptrFromInt(registers), aligned_buffer);
    }

    return self;
}

pub fn initialize(self: *Self, allocator: Allocator) !void {
    try self.transfer_mailbox.init(allocator, 1024);

    try self.powerOn();
    try self.verifyHostControllerDevice();
    try self.resetSoft();
    try self.initializeControllerCore();
    try self.initializeInterrupts();

    // higher priority so it gets scheduled ahead of the application
    // thread
    const DRIVER_THREAD_PRIO = 200;
    self.driver_thread = try schedule.spawnWithOptions(dwcDriverLoop, self, &.{
        .name = "dwc driver",
        .priority = DRIVER_THREAD_PRIO,
        .schedule = false,
    });
}

fn powerOn(self: *Self) !void {
    const power_result = try self.power_controller.powerOn(POWER_DEVICE_USB_HCD);

    if (power_result != .power_on) {
        log.err("Failed to power on USB device: {any}", .{power_result});
        return Error.PowerFailure;
    }

    // wait a bit for power to settle
    time.delayMillis(10);
}

fn powerOff(self: *Self) !void {
    const power_result = try self.power_controller.powerOff(POWER_DEVICE_USB_HCD);

    if (power_result != .power_off) {
        log.err("Failed to power off USB device: {any}", .{power_result});
        return Error.PowerFailure;
    }
}

fn verifyHostControllerDevice(self: *Self) !void {
    const id = self.core_registers.vendor_id;

    log.info("DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

    if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
        log.warn(" gsnpsid = {x:0>8}\nvendor = {x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
        return Error.IncorrectDevice;
    }
}

fn initializeControllerCore(self: *Self) !void {
    // clear bits 20 & 22 of core usb config register
    var config: UsbConfig = self.core_registers.usb_config;
    config.ulpi_ext_vbus_drv = 0;
    config.term_sel_dl_pulse = 0;
    self.core_registers.usb_config = config;

    config.mode_select = .ulpi;
    config.phy_if = 0;
    self.core_registers.usb_config = config;

    // need another reset to make the phy changes take effect
    try self.resetSoft();

    const hw2 = self.core_registers.hardware_config_2;
    config = self.core_registers.usb_config;
    if (hw2.high_speed_physical_type == .ulpi and hw2.full_speed_physical_type == .dedicated) {
        config.ulpi_fsls = 1;
        config.ulpi_clk_sus_m = 1;
    } else {
        config.ulpi_fsls = 0;
        config.ulpi_clk_sus_m = 0;
    }
    self.core_registers.usb_config = config;

    self.num_host_channels = hw2.num_host_channels;

    self.power_and_clock_control.* = @bitCast(@as(u32, 0));

    try self.configPhyClockSpeed();

    self.host_registers.config.fs_ls_support_only = 1;

    const rx_words: u32 = 1024; // Size of Rx FIFO in 4-byte words
    const tx_words: u32 = 1024; // Size of Non-periodic Tx FIFO in 4-byte words
    const ptx_words: u32 = 1024; // Size of Periodic Tx FIFO in 4-byte words

    // Configure FIFO sizes. Required because the defaults do not work correctly.

    self.core_registers.rx_fifo_size = @bitCast(rx_words);
    self.core_registers.nonperiodic_tx_fifo_size = @bitCast((tx_words << 16) | rx_words);
    self.core_registers.host_periodic_tx_fifo_size = @bitCast((ptx_words << 16) | (rx_words + tx_words));

    var ahb = self.core_registers.ahb_config;
    ahb.dma_enable = 1;
    ahb.dma_remainder_mode = .incremental;
    ahb.wait_for_axi_writes = 1;
    ahb.max_axi_burst = 0;
    self.core_registers.ahb_config = ahb;

    config = self.core_registers.usb_config;
    switch (hw2.operating_mode) {
        .hnp_srp_capable_otg => {
            config.hnp_capable = 1;
            config.srp_capable = 1;
        },
        .srp_only_capable_otg, .srp_capable_device, .srp_capable_host => {
            config.hnp_capable = 0;
            config.srp_capable = 1;
        },
        .no_hnp_src_capable_otg, .no_srp_capable_host, .no_srp_capable_device => {
            config.hnp_capable = 0;
            config.srp_capable = 0;
        },
        else => {
            config.hnp_capable = 0;
            config.srp_capable = 0;
        },
    }
    self.core_registers.usb_config = config;
}

fn resetSoft(self: *Self) !void {
    // log.debug("core controller reset", .{});

    // trigger the soft reset
    self.core_registers.reset.soft_reset = 1;

    // wait up to 10 ms for reset to finish
    const reset_end = time.deadlineMillis(10);

    // TODO what should we do if we don't see the soft_reset go to zero?
    while (time.ticks() < reset_end and self.core_registers.reset.soft_reset != 0) {}

    if (self.core_registers.reset.soft_reset != 0) {
        return Error.InitializationFailure;
    }

    // wait 100 ms
    time.delayMillis(100);
}

fn initializeInterrupts(self: *Self) !void {
    // Enable only host channel and port interrupts
    var enabled: InterruptMask = @bitCast(@as(u32, 0));
    enabled.host_channel = 1;
    enabled.port = 1;
    self.core_registers.core_interrupt_mask = enabled;

    // Clear pending interrupts
    const clear_all: InterruptStatus = @bitCast(@as(u32, 0xffff_ffff));
    self.core_registers.core_interrupt_status = clear_all;

    // Clear the channel interrupts mask and any pending interrupt bits
    self.host_registers.all_channel_interrupts_mask = @bitCast(@as(u32, 0));
    self.host_registers.all_channel_interrupts = @bitCast(clear_all);

    // Connect interrupt handler & enable interrupts on the ARM PE
    self.intc.connect(self.irq_id, &self.irq_handler, self);
    self.intc.enable(self.irq_id);

    // Enable interrupts for the host controller (this is the DWC side)
    self.core_registers.ahb_config.global_interrupt_enable = 1;

    log.debug("initializeInterrupts: mask = 0x{x:0>8}, status = 0x{x:0>8}", .{
        @as(u32, @bitCast(self.core_registers.core_interrupt_mask)),
        @as(u32, @bitCast(self.core_registers.core_interrupt_status)),
    });
}

fn configPhyClockSpeed(self: *Self) !void {
    const core_config = self.core_registers.usb_config;
    const hw2 = self.core_registers.hardware_config_2;
    if (hw2.high_speed_physical_type == .ulpi and hw2.full_speed_physical_type == .dedicated and core_config.ulpi_fsls == 1) {
        self.host_registers.config.clock_rate = .clock_48_mhz;
    } else {
        self.host_registers.config.clock_rate = .clock_30_60_mhz;
    }
}

fn haltAllChannels(self: *Self) !void {
    for (0..self.num_host_channels) |chid| {
        var char = self.channels[chid].registers.channel_character;
        char.enable = true;
        char.disable = true;
        char.endpoint_direction = .in;
        self.registers.channel_character = char;

        // wait until we see enable go low
        const enable_wait_end = time.deadlineMillis(100);
        while (self.channels[chid].regisers.channel_character.enable == 1 and time.ticks() < enable_wait_end) {}
    }
}

// ----------------------------------------------------------------------
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(_: *InterruptController, _: IrqId, private: ?*anyopaque) void {
    _ = atomic.atomicReset(&schedule.resdefer, 1);

    var self: *Self = @ptrCast(@alignCast(private));

    const intr_status = self.core_registers.core_interrupt_status;

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel == 1) {
        const all_intrs = self.host_registers.all_channel_interrupts;
        //        self.host_registers.all_channel_interrupts = all_intrs;
        log.debug("irq handle: host channel ints 0x{x:0>8}", .{@as(u32, @bitCast(all_intrs))});

        // Find the channel that has something to say
        var channel_mask: u32 = 1;
        // TODO consider using @ctz to find the lowest bit that's set,
        // instead of looping over all 16 channels.
        for (0..dwc_max_channels) |chid| {
            if ((all_intrs & channel_mask) != 0) {
                self.channels[chid].channelInterrupt2(self);
            }
            channel_mask <<= 1;
        }
    }

    // check if the host port raised the interrupt
    if (intr_status.port == 1) {
        // pass it on to the root hub
        self.root_hub.hubHandlePortInterrupt();
    }

    // clear the interrupt bits
    self.core_registers.core_interrupt_status = intr_status;

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

pub fn dumpStatus(self: *Self) void {
    log.info("{s: >28}", .{"Core registers"});
    dumpRegisterPair(
        "otg_control",
        @bitCast(self.core_registers.otg_control),
        "ahb_config",
        @bitCast(self.core_registers.ahb_config),
    );
    dumpRegisterPair(
        "usb_config",
        @bitCast(self.core_registers.usb_config),
        "reset",
        @bitCast(self.core_registers.reset),
    );
    dumpRegisterPair(
        "hw_config_1",
        @bitCast(self.core_registers.hardware_config_1),
        "hw_config_2",
        @bitCast(self.core_registers.hardware_config_2),
    );
    dumpRegisterPair(
        "interrupt_status",
        @bitCast(self.core_registers.core_interrupt_status),
        "interrupt_mask",
        @bitCast(self.core_registers.core_interrupt_mask),
    );
    dumpRegisterPair(
        "rx_status",
        @bitCast(self.core_registers.rx_status_read),
        "rx_fifo_size",
        @bitCast(self.core_registers.rx_fifo_size),
    );
    dumpRegisterPair(
        "nonperiodic_tx_fifo_size",
        @bitCast(self.core_registers.nonperiodic_tx_fifo_size),
        "nonperiodic_tx_status",
        @bitCast(self.core_registers.nonperiodic_tx_status),
    );

    log.info("", .{});
    log.info("{s: >28}", .{"Host registers"});
    dumpRegisterPair("port", @bitCast(self.host_registers.port), "config", @bitCast(self.host_registers.config));
    dumpRegisterPair("frame_interval", @bitCast(self.host_registers.frame_interval), "frame_num", @bitCast(self.host_registers.frame_num));
    dumpRegisterPair("all_channel_interrupts", @bitCast(self.host_registers.all_channel_interrupts), "all_channel_interrupts_mask", @bitCast(self.host_registers.all_channel_interrupts_mask));
}

pub fn dumpRegisterPair(f1: []const u8, v1: u32, f2: []const u8, v2: u32) void {
    log.info("{s: >28}: {x:0>8}\t{s: >28}: {x:0>8}", .{ f1, v1, f2, v2 });
}

fn dumpRegister(field_name: []const u8, v: u32) void {
    log.info("{s: >28}: {x:0>8}", .{ field_name, v });
}

// ----------------------------------------------------------------------
// Channel handling
// ----------------------------------------------------------------------
fn channelAllocate(self: *Self) !*Channel {
    const chid = try self.channel_assignments.allocate();
    errdefer self.channel_assignments.free(chid);

    if (chid >= self.num_host_channels) {
        return error.NoAvailableChannel;
    }

    const ch = &self.channels[chid];
    return ch;
}

pub fn channelFree(self: *Self, channel: *Channel) void {
    self.channel_assignments.free(channel.id);
}

fn channelInterruptEnable(self: *Self, channel: Channel.ChannelId) void {
    _ = channel;
    _ = self;
    // log.debug("interrupt enable channel {d}", .{channel});

}

fn channelInterruptDisable(self: *Self, channel: Channel.ChannelId) void {
    // log.debug("interrupt disable channel {d}", .{channel});

    self.all_channel_intmask_lock.acquire();
    defer self.all_channel_intmask_lock.release();
    self.host_registers.all_channel_interrupts_mask &= ~(@as(u32, 1) << channel);
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
pub fn perform(self: *Self, xfer: *TransferRequest) !void {
    // put the transfer in the pending_transfers list.
    try self.transfer_mailbox.send(xfer);
}

/// Start or restart a transfer on a channel of the HCD
pub fn channelStartTransfer(self: *Self, channel: *Channel, req: *TransferRequest) void {
    var characteristics: ChannelCharacteristics = @bitCast(@as(u32, 0));
    var split_control: SplitControl = @bitCast(@as(u32, 0));
    var transfer: TransferSize = @bitCast(@as(u32, 0));
    var data: ?[*]u8 = null;

    req.short_attempt = false;

    if (req.endpoint_desc) |ep| {
        characteristics.endpoint_number = @truncate(ep.endpoint_address & 0xf);
        characteristics.endpoint_type = ep.attributes.endpoint_type;
        characteristics.max_packet_size = @truncate(ep.max_packet_size & 0x7ff);
        characteristics.packets_per_frame = 1;
        if (req.device != null and req.device.?.speed == UsbSpeed.High) {
            characteristics.packets_per_frame += @truncate((ep.max_packet_size >> 11) & 0x3);
        }

        log.debug("channel start transfer to endpoint {d} mps {d}", .{ characteristics.endpoint_number, characteristics.max_packet_size });
    } else {
        // This transfer aims at the default control
        // endpoint. (Endpoint 0.)
        log.debug("channel start transfer to default control endpoint", .{});
        characteristics.endpoint_number = 0;
        characteristics.endpoint_type = TransferType.control;
        characteristics.max_packet_size = req.device.?.device_descriptor.max_packet_size;
        characteristics.packets_per_frame = 1;
    }

    if (characteristics.endpoint_type == TransferType.control) {
        switch (req.control_phase) {
            TransferRequest.control_setup_phase => {
                debugLogTransfer(req, "starting SETUP transaction");
                characteristics.endpoint_direction = EndpointDirection.out;
                data = @ptrCast(&req.setup_data);
                transfer.size = @sizeOf(SetupPacket);
                transfer.packet_id = DwcTransferSizePid.setup;

                debug.sliceDump(std.mem.asBytes(&req.setup_data));
            },
            TransferRequest.control_data_phase => {
                debugLogTransfer(req, "starting DATA transaction");
                characteristics.endpoint_direction = req.setup_data.request_type.transfer_direction;
                data = req.data + req.actual_size;
                transfer.size = @truncate(req.size - req.actual_size);
                if (req.actual_size == 0) {
                    transfer.packet_id = DwcTransferSizePid.data1;
                } else {
                    transfer.packet_id = req.next_data_pid;
                }
            },
            else => {
                debugLogTransfer(req, "starting STATUS transaction");

                if (req.setup_data.request_type.transfer_direction == EndpointDirection.out or
                    req.setup_data.data_size == 0)
                {
                    characteristics.endpoint_direction = EndpointDirection.in;
                } else {
                    characteristics.endpoint_direction = EndpointDirection.out;
                }
                data = null;
                transfer.size = 0;
                transfer.packet_id = DwcTransferSizePid.data1;
            },
        }
    } else {
        // non-control transfer, either starting for the first time or
        // restarting (maybe after being deferred)
        characteristics.endpoint_direction = req.endpoint_desc.?.direction();
        data = req.data + req.actual_size;
        transfer.size = @truncate(req.size - req.actual_size);

        if (characteristics.endpoint_type == TransferType.interrupt) {
            if (transfer.size > characteristics.packets_per_frame * characteristics.max_packet_size) {
                transfer.size = characteristics.packets_per_frame * characteristics.max_packet_size;
                req.short_attempt = true;
            } else {
                const mps = characteristics.max_packet_size;
                transfer.size = @truncate((transfer.size + mps - 1) / mps);
            }
        }

        transfer.packet_id = req.next_data_pid;

        debugLogTransfer(req, "starting transaction");
    }

    characteristics.device_address = req.device.?.address;

    // if talking to a low or full speed device, handle the
    // split register
    if (req.device.?.speed != UsbSpeed.High) {
        // log.debug("device needs a split transaction, finding TT", .{});

        // find which hub is the transaction translator (TT)
        var tt_hub_port: u7 = 0;
        var tt_hub: ?*Device = req.device.?;

        // TODO - is this guaranteed to finish?
        while (tt_hub != null and tt_hub.?.speed != UsbSpeed.High) {
            tt_hub_port = tt_hub.?.port_number;
            tt_hub = tt_hub.?.parent;
        }

        split_control.port_address = if (tt_hub_port >= 1) tt_hub_port - 1 else 0;
        split_control.hub_address = if (tt_hub) |h| h.address else 0;
        split_control.split_enable = 1;

        // log.debug("split control: port {d}, hub {d}, enable {d}", .{ split_control.port_address, split_control.hub_address, split_control.split_enable });

        if (transfer.size > characteristics.max_packet_size) {
            transfer.size = characteristics.max_packet_size;
            req.short_attempt = true;
        }

        characteristics.low_speed_device = switch (req.device.?.speed) {
            .Low => 1,
            else => 0,
        };
    }

    if (data == null) {
        channel.registers.channel_dma_addr = 0;
    } else if (isAligned(data.?)) {
        channel.registers.channel_dma_addr = @truncate(@intFromPtr(data.?));
    } else {
        channel.registers.channel_dma_addr = @truncate(@intFromPtr(channel.aligned_buffer.ptr));

        // the aligned buffer is a fixed size, so it might not be big
        // enough to hold the entire transmission. we will do as much
        // as possible
        const buflen = channel.aligned_buffer.len;
        if (transfer.size > buflen) {
            const max_full_packets = buflen - (buflen % characteristics.max_packet_size);
            transfer.size = @truncate(max_full_packets);
            req.short_attempt = true;
        }

        // if we are sending data, copy it into the aligned buffer
        if (characteristics.endpoint_direction == 0) {
            @memcpy(channel.aligned_buffer[0..transfer.size], data.?);
        }
    }

    // It's OK if this doesn't match the DMA address selected
    // above. We mostly use this to track the # of bytes remaining to
    // send or receive
    req.cur_data_ptr = data;

    if (channel.registers.channel_dma_addr & (DMA_ALIGNMENT - 1) != 0) {
        log.warn("data ptr 0x{x:0>8} misaligned by 0x{x} bytes", .{ channel.registers.channel_dma_addr, (channel.registers.channel_dma_addr & (DMA_ALIGNMENT - 1)) });
    }

    const mps = characteristics.max_packet_size;
    transfer.packet_count = @truncate((transfer.size + mps - 1) / mps);

    if (transfer.packet_count == 0) {
        transfer.packet_count = 1;
    }

    req.attempted_size = transfer.size;
    req.attempted_bytes_remaining = transfer.size;
    req.attempted_packets_remaining = transfer.packet_count;

    channel.active_transfer = req;

    log.info("Setting up transactions on channel {d}:\n" ++
        "\t\tmax_packet_size={d}, " ++
        "endpoint_number={d}, endpoint_direction={d},\n" ++
        "\t\tlow_speed={d}, endpoint_type={d}, device_address={d},\n\t\t" ++
        "size={d}, packet_count={d}, packet_id={d}, split_enable={d}, complete_split={}", .{
        channel.id,
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

    channel.registers.channel_character = characteristics;
    channel.registers.split_control = split_control;
    channel.registers.transfer = transfer;

    // enable the channel
    self.channelStartTransaction(channel, req);
}

// requires the following registers were already configured:
// - channel characteristics
// - transfer size
// - dma address
pub fn channelStartTransaction(self: *Self, channel: *Channel, req: *TransferRequest) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    // Clear pending interrupts
    channel.registers.channel_int_mask = @bitCast(@as(u32, 0));
    channel.registers.channel_int = @bitCast(@as(u32, 0xffff_ffff));

    // is this the completion part of a split transaction?
    var split_control = channel.registers.split_control;
    split_control.complete_split = if (req.complete_split) 1 else 0;
    channel.registers.split_control = split_control;

    // set odd frame and enable
    const next_frame = (self.host_registers.frame_num.number & 0xffff) + 1;

    if (split_control.complete_split == 0) {
        req.csplit_retries = 0;
    }

    channel.registers.channel_int_mask = active_transaction_interrupts;
    self.host_registers.all_channel_interrupts_mask |= @as(u32, 1) << channel.id;

    var channel_char = channel.registers.channel_character;
    channel_char.odd_frame = @truncate(next_frame & 1);
    channel_char.enable = 1;
    channel_char.disable = 0;
    channel.registers.channel_character = channel_char;
}

const active_transaction_interrupts: ChannelInterrupt = .{
    .halt = 1,
};

// ----------------------------------------------------------------------
// Deferred transfer support
// ----------------------------------------------------------------------

const DeferredTransferArgs = struct {
    host: *Self,
    req: *TransferRequest,
};

pub fn deferTransfer(self: *Self, req: *TransferRequest) !void {
    debugLogTransfer(req, "deferring");

    // first time through, allocate a semaphore
    // if the request is deferred more than once, the semaphore is reused
    if (req.deferrer_thread_sem == null) {
        req.deferrer_thread_sem = try semaphore.create(0);
        errdefer {
            semaphore.free(req.deferrer_thread_sem.?);
            req.deferrer_thread_sem = null;
        }
        log.debug("created semaphore {d} for deferred transfer", .{req.deferrer_thread_sem.?});
    }

    // first time through, allocate a thread.
    // if the request is deferred more than once, the thread is reused
    if (req.deferrer_thread == null) {
        var args: DeferredTransferArgs = .{
            .host = self,
            .req = req,
        };
        req.deferrer_thread = try schedule.spawn(deferredTransfer, "dwc defer", &args);
        log.debug("spawned thread {d} for deferred transfer", .{req.deferrer_thread.?});
    }

    // let the thread progress
    semaphore.signal(req.deferrer_thread_sem.?) catch {};
}

fn deferredTransfer(args_ptr: *anyopaque) void {
    const args: *DeferredTransferArgs = @ptrCast(@alignCast(args_ptr));
    const req = args.req;
    const host = args.host;

    var interval_ms: u32 = 0;

    if (req.device.?.speed == UsbSpeed.High) {
        interval_ms = (@as(u32, 1) << @as(u5, @truncate(req.endpoint_desc.?.interval)) - 1) / USB_UFRAMES_PER_MS;
    } else {
        interval_ms = req.endpoint_desc.?.interval / USB_FRAMES_PER_MS;
    }

    if (interval_ms == 0) {
        interval_ms = 1;
    }

    while (true) {
        semaphore.wait(req.deferrer_thread_sem.?) catch |err| {
            log.err("deferredTransfer semaphore {d} error {any}", .{ req.deferrer_thread_sem.?, err });
            // TODO something
        };

        log.debug("deferring transfer for {d}ms", .{interval_ms});

        schedule.sleep(interval_ms) catch |err| {
            log.err("deferredTransfer sleep error {any}", .{err});
            // TODO something
        };

        if (host.channelAllocate()) |channel| {
            host.channelStartTransfer(channel, req);
        } else |err| {
            log.err("channel allocate error: {any}", .{err});
        }
    }
}

fn debugLogTransfer(req: *TransferRequest, msg: []const u8) void {
    var transfer_type: []const u8 = "control";
    var endpoint_number: u8 = 0;

    if (req.endpoint_desc) |ep| {
        endpoint_number = ep.endpoint_address;
        switch (ep.attributes.endpoint_type) {
            0b00 => transfer_type = "control",
            0b01 => transfer_type = "isochronous",
            0b10 => transfer_type = "bulk",
            0b11 => transfer_type = "interrupt",
        }
    }

    log.info("[{d}:{d} {s}] {s}", .{ req.device.?.address, endpoint_number, transfer_type, msg });
}

// ----------------------------------------------------------------------
// Main driver thread
// ----------------------------------------------------------------------

fn signalShutdown(self: *Self) void {
    self.shutdown_signal.signal();
}

fn isShuttingDown(self: *Self) bool {
    return self.shutdown_signal.isSignalled();
}

/// Driver thread proc
pub fn dwcDriverLoop(args: *anyopaque) void {
    const self: *Self = @alignCast(@ptrCast(args));

    while (!self.isShuttingDown()) {
        if (self.transfer_mailbox.receive()) |xfer| {
            //            debugLogTransfer(xfer, "begin");
            if (xfer.device) |dev| {
                if (dev.isRootHub()) {
                    self.root_hub.hubHandleTransfer(xfer);
                } else {
                    if (self.channelAllocate()) |channel| {
                        self.channelStartTransfer(channel, xfer);
                    } else |err| {
                        log.err("channel allocate error: {any}", .{err});
                    }
                }
            } else {
                log.err("malformed transfer: no device", .{});
            }
        } else |err| {
            log.err("transfer_mailbox receive error: {any}", .{err});
        }
    }
}
