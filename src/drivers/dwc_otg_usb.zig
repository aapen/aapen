const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;
const PendingTransfers = DoublyLinkedList(*Transfer);

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
const Transfer = usb.Transfer;
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
pub const DMA_ALIGNMENT = 64;

const HcdChannels = ChannelSet.init("dwc_otg_usb channels", u5, dwc_max_channels);
const UsbTransferMailbox = Mailbox(*Transfer);

const empty_slice: []u8 = &[_]u8{};

allocator: Allocator,
core_registers: *volatile CoreRegisters,
host_registers: *volatile HostRegisters,
power_and_clock_control: *volatile PowerAndClock,
all_channel_intmask_lock: TicketLock,
intc: *InterruptController,
irq_id: IrqId,
irq_handler: IrqHandler = .{
    .callback = irqHandle,
},
translations: *const AddressTranslations,
power_controller: *PowerController,
num_host_channels: u4,
channel_assignments: HcdChannels = .{},
channels: [dwc_max_channels]Channel = [_]Channel{.{}} ** dwc_max_channels,
root_hub: RootHub = .{},
transfer_mailbox: UsbTransferMailbox,
driver_thread: schedule.TID,
shutdown_signal: OneShot = .{},

// Ideas for improving this:
// - reserve an aligned buffer for each channel to use. that avoids
//   dynamic allocation in the inner loop

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
        const channel_registers: *volatile ChannelRegisters = @ptrFromInt(register_base + 0x500 + (@sizeOf(ChannelRegisters) * chid));
        self.channels[chid].init(@truncate(chid), channel_registers);
    }

    return self;
}

pub fn initialize(self: *Self, allocator: Allocator) !void {
    // higher priority so it gets scheduled ahead of the application
    // thread
    const DRIVER_THREAD_PRIO = 200;
    self.driver_thread = try schedule.spawnWithOptions(dwcDriverLoop, self, &.{
        .name = "dwc driver",
        .priority = DRIVER_THREAD_PRIO,
        .schedule = false,
    });

    try self.transfer_mailbox.init(allocator, 1024);

    try self.powerOn();
    try self.verifyHostControllerDevice();
    try self.resetSoft();
    try self.initializeControllerCore();
    try self.initializeInterrupts();

    //    self.pending_transfers_lock.enabled = true;
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

    log.debug("{d} words of RAM available for dynamic FIFOs", .{@as(u32, @bitCast(self.core_registers.hardware_config_3)) >> 16});
    log.debug("original FIFO sizes: rx 0x{x:0>8}, tx 0x{x:0>8}, ptx 0x{x:0>8}", .{ @as(u32, @bitCast(self.core_registers.rx_fifo_size)), @as(u32, @bitCast(self.core_registers.nonperiodic_tx_fifo_size)), @as(u32, @bitCast(self.core_registers.host_periodic_tx_fifo_size)) });

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
    log.debug("core controller reset", .{});

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

    // Connect interrupt handler & enable interrupts on the ARM PE
    self.intc.connect(self.irq_id, &self.irq_handler);
    self.intc.enable(self.irq_id);

    // Enable interrupts for the host controller (this is the DWC side)
    self.core_registers.ahb_config.global_interrupt_enable = 1;
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
fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    var self = @fieldParentPtr(Self, "irq_handler", this);

    const intr_status = self.core_registers.core_interrupt_status;

    log.debug("irq handle: intr_status 0x{x:0>8}", .{@as(u32, @bitCast(intr_status))});

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel == 1) {
        const all_intrs = self.host_registers.all_channel_interrupts;
        //        self.host_registers.all_channel_interrupts = all_intrs;
        log.debug("irq handle: channel intr 0x{x:0>8}", .{@as(u32, @bitCast(all_intrs))});

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

fn dumpRegisterPair(f1: []const u8, v1: u32, f2: []const u8, v2: u32) void {
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
    return &self.channels[chid];
}

pub fn channelFree(self: *Self, channel: *Channel) void {
    self.channel_assignments.free(channel.id);
}

fn channelInterruptEnable(self: *Self, channel: Channel.ChannelId) void {
    log.debug("interrupt enable channel {d}", .{channel});

    self.all_channel_intmask_lock.acquire();
    defer self.all_channel_intmask_lock.release();
    self.host_registers.all_channel_interrupts_mask |= @as(u32, 1) << channel;
}

fn channelInterruptDisable(self: *Self, channel: Channel.ChannelId) void {
    log.debug("interrupt disable channel {d}", .{channel});

    self.all_channel_intmask_lock.acquire();
    defer self.all_channel_intmask_lock.release();
    self.host_registers.all_channel_interrupts_mask &= ~(@as(u32, 1) << channel);
}

// fn transactionOnChannel(
//     self: *Self,
//     device: DeviceAddress,
//     device_speed: UsbSpeed,
//     endpoint_number: EndpointNumber,
//     endpoint_type: u2,
//     endpoint_direction: u1,
//     max_packet_size: PacketSize,
//     initial_pid: u4,
//     buffer: []u8,
//     timeout: u32,
// ) !TransferBytes {
//     var transaction = Transaction{
//         .host = self,
//         .actual_length = 0,
//     };

//     log.debug("Acquiring channel", .{});

//     var channel = try self.channelAllocate();
//     defer self.channelFree(channel);

//     log.debug("Received channel {d}", .{channel.id});

//     self.channelInterruptEnable(channel.id);
//     defer self.channelInterruptDisable(channel.id);

//     transaction.deadline = if (timeout == 0) 0 else time.deadlineMillis(timeout);

//     try channel.transactionBegin(device, device_speed, endpoint_number, endpoint_type, endpoint_direction, max_packet_size, initial_pid, buffer, &transaction.completion_handler);

//     while (time.ticks() < transaction.deadline and !transaction.completed) {}

//     // wait for transaction.completed to be true, or deadline elapsed.
//     if (transaction.completed) {
//         if (transaction.succeeded) {
//             log.debug("Transaction succeeded", .{});
//             return transaction.actual_length;
//         } else {
//             log.debug("Transaction halted", .{});
//             return 0;
//         }
//     } else {
//         log.warn("Transaction timed out on channel {d}", .{channel.id});
//         // if timeout, abort the transaction
//         channel.channelAbort();

//         try channel.waitForState(.Idle, 100);

//         return 0;
//     }
// }

// ----------------------------------------------------------------------
// Transfer interface - high level
// ----------------------------------------------------------------------

// this is called from application threads
pub fn perform(self: *Self, xfer: *Transfer) !void {
    // put the transfer in the pending_transfers list.
    try self.transfer_mailbox.send(xfer);
}

/// Start or restart a transfer on a channel of the HCD
pub fn channelStartTransfer(self: *Self, channel: *Channel, xfer: *Transfer) void {
    var channel_char: ChannelCharacteristics = undefined;
    var channel_split: ChannelSplitControl = undefined;
    _ = channel_split;
    var channel_transfer: TransferSize = undefined;
    var data: []u8 = undefined;

    xfer.short_attempt = false;

    if (xfer.endpoint_descriptor) |epdesc| {
        channel_char.endpoint_number = @truncate(epdesc.endpoint_address & 0xf);
        channel_char.endpoint_type = epdesc.attributes.endpoint_type;
        channel_char.max_packet_size = @truncate(epdesc.max_packet_size & 0x7ff);
        channel_char.packets_per_frame = 1;
        if (xfer.device != null and xfer.device.?.speed == UsbSpeed.High) {
            channel_char.packets_per_frame += @truncate((epdesc.max_packet_size >> 11) & 0x3);
        }

        log.debug("channel start transfer to endpoint {d} mps {d}", .{ channel_char.endpoint_number, channel_char.max_packet_size });
    } else {
        // This transfer aims at the default control
        // endpoint. (Endpoint 0.)
        log.debug("channel start transfer to default control endpoint", .{});

        channel_char.endpoint_number = 0;
        channel_char.endpoint_type = TransferType.control;
        if (xfer.device) |dev| {
            channel_char.max_packet_size = dev.device_descriptor.max_packet_size;
        }
        channel_char.packets_per_frame = 1;
    }

    if (channel_char.endpoint_type == TransferType.control) {
        switch (xfer.control_phase) {
            Transfer.ControlPhase.setup => {
                log.debug("Starting setup transaction", .{});
                channel_char.endpoint_direction = EndpointDirection.out;
                data = std.mem.asBytes(&xfer.setup);
                channel_transfer.transfer_size_bytes = @sizeOf(SetupPacket);
                channel_transfer.pid = DwcTransferSizePid.setup;
            },
            Transfer.ControlPhase.data => {
                log.debug("Starting data transaction", .{});
                channel_char.endpoint_direction = xfer.setup.request_type.transfer_direction;
                data = xfer.data_buffer[xfer.actual_size..];
                channel_transfer.transfer_size_bytes = @truncate(xfer.data_buffer.len - xfer.actual_size);
                if (xfer.actual_size == 0) {
                    channel_transfer.pid = DwcTransferSizePid.data1;
                } else {
                    channel_transfer.pid = xfer.next_data_pid;
                }
            },
            else => {
                log.debug("Starting status transaction", .{});
                if (xfer.setup.request_type.transfer_direction == EndpointDirection.out or
                    xfer.setup.data_size == 0)
                {
                    channel_char.endpoint_direction = EndpointDirection.in;
                } else {
                    channel_char.endpoint_direction = EndpointDirection.out;
                }
                data = empty_slice;
                channel_transfer.transfer_size_bytes = 0;
                channel_transfer.pid = DwcTransferSizePid.data1;
            },
        }
    } else {
        // non-control transfer
        channel_char.endpoint_direction = xfer.endpoint_descriptor.?.direction();
        data = xfer.data_buffer[xfer.actual_size..];
        channel_transfer.transfer_size_bytes = @truncate(xfer.data_buffer.len - xfer.actual_size);
        if (channel_char.endpoint_type == TransferType.interrupt and
            channel_transfer.transfer_size_bytes > channel_char.packets_per_frame * channel_char.max_packet_size)
        {
            channel_transfer.transfer_size_bytes = channel_char.packets_per_frame * channel_char.max_packet_size;
            xfer.short_attempt = true;
        }
        channel_transfer.pid = xfer.next_data_pid;

        log.debug("Starting transaction type {d} with {d} bytes", .{ channel_char.endpoint_type, channel_transfer.transfer_size_bytes });
    }

    channel_char.device_address = xfer.device.?.address;

    // TODO - if talking to a low or full speed device, handle the
    // split register

    channel_char.low_speed_device = switch (xfer.device.?.speed) {
        .Low => 1,
        else => 0,
    };

    channel.registers.channel_dma_addr = @truncate(@intFromPtr(data.ptr));
    channel_transfer.transfer_size_packets = @truncate((channel_transfer.transfer_size_bytes + channel_char.max_packet_size - 1) / channel_char.max_packet_size);
    if (channel_transfer.transfer_size_packets == 0) {
        channel_transfer.transfer_size_packets = 1;
    }

    xfer.attempted_size = channel_transfer.transfer_size_bytes;
    xfer.attempted_bytes_remaining = channel_transfer.transfer_size_bytes;
    xfer.attempted_packets_remaining = channel_transfer.transfer_size_packets;

    channel.active_transfer = xfer;

    log.debug("Setting up transactions on channel {d}:\n" ++
        "\t\tmax_packet_size={d}, " ++
        "endpoint_number={d}, endpoint_direction={d},\n" ++
        "\t\tlow_speed={d}, endpoint_type={d}, device_address={d},\n\t\t" ++
        "size={d}, packet_count={d}, packet_id={d}", .{
        channel.id,
        channel_char.max_packet_size,
        channel_char.endpoint_number,
        channel_char.endpoint_direction,
        channel_char.low_speed_device,
        channel_char.endpoint_type,
        channel_char.device_address,
        channel_transfer.transfer_size_bytes,
        channel_transfer.transfer_size_packets,
        channel_transfer.pid,
    });

    if (channel_char.endpoint_direction == 0) {
        // for 'out' transactions, dump the buffer
        debug.sliceDump(data);
    }

    channel.registers.channel_character = channel_char;
    channel.registers.channel_transfer_size = channel_transfer;

    // enable the channel
    self.channelStartTransaction(channel, xfer);
}

const active_transaction_interrupts: ChannelInterrupt = .{
    .transfer_complete = 1,
    .halt = 1,
    .ahb_error = 1,
    .stall = 1,
    .nak = 1,
    .ack = 1,
    .nyet = 1,
    .transaction_error = 1,
    .babble_error = 1,
    .frame_overrun = 1,
    .data_toggle_error = 1,
    .buffer_not_available = 1,
    .excessive_transmission = 1,
    .frame_list_rollover = 1,
};

// requires the following registers were already configured:
// - channel characteristics
// - transfer size
// - dma address
pub fn channelStartTransaction(self: *Self, channel: *Channel, xfer: *Transfer) void {
    _ = xfer;
    const im = cpu.disable();
    defer cpu.restore(im);

    // Clear pending interrupts
    channel.interruptsClearPending();
    channel.registers.channel_int_mask = @bitCast(@as(u32, 0));

    // TODO handle split completion

    // set odd frame and enable
    var channel_char = channel.registers.channel_character;
    const next_frame = (self.host_registers.frame_num.number & 0xffff) + 1;
    channel_char.odd_frame = @truncate(next_frame & 1);
    channel.registers.channel_character = channel_char;

    channel.interruptsEnableActiveTransaction();
    self.channelInterruptEnable(channel.id);

    channel.enable();
}

// fn processTransfer(self: *Self, xfer: *Transfer) !void {
//     // This driver-level routine assumes that a higher-level caller
//     // has already checked the Transfer's consistency against USB
//     // specifications

//     // TODO this is too simplistic... it will fail if all channels are
//     // occupied. A better way would be to enqueue a Request and have a
//     // timer- or interrupt-driven dispatcher place transactions on
//     // channels as when they are available.

//     // old implementation below here.
//     while (xfer.state != .complete) {
//         switch (xfer.endpoint_type) {
//             TransferType.control => {
//                 switch (xfer.state) {
//                     .token => {
//                         const aligned_buffer = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(SetupPacket));
//                         defer self.allocator.free(aligned_buffer);

//                         @memcpy(aligned_buffer, std.mem.asBytes(&xfer.setup));

//                         log.debug("perform: performing 'setup' transaction with rt = {b}, rq = {d}, mps = {d}", .{ @as(u8, @bitCast(xfer.setup.request_type)), xfer.setup.request, xfer.max_packet_size });

//                         const maybe_setup_response = self.transactionOnChannel(
//                             xfer.device_address,
//                             xfer.device_speed,
//                             xfer.endpoint_number,
//                             xfer.endpoint_type,
//                             EndpointDirection.out,
//                             xfer.max_packet_size,
//                             xfer.getTransactionPid(),
//                             aligned_buffer,
//                             DEFAULT_TRANSFER_TIMEOUT,
//                         );

//                         if (maybe_setup_response) |bytes| {
//                             if (bytes == @sizeOf(SetupPacket)) {
//                                 xfer.transferCompleteTransaction(.ok);
//                             } else {
//                                 xfer.transferCompleteTransaction(.data_length_mismatch);
//                             }
//                         } else |_| {
//                             xfer.transferCompleteTransaction(.failed);
//                         }
//                     },
//                     .data => {
//                         log.debug("perform: performing 'data' transaction with {any}", .{xfer.setup.request_type.transfer_direction});

//                         const data_direction = switch (xfer.setup.request_type.transfer_direction) {
//                             RequestTypeDirection.host_to_device => EndpointDirection.out,
//                             RequestTypeDirection.device_to_host => EndpointDirection.in,
//                         };

//                         const maybe_in_data_response = self.transactionOnChannel(
//                             xfer.device_address,
//                             xfer.device_speed,
//                             xfer.endpoint_number,
//                             xfer.endpoint_type,
//                             data_direction,
//                             xfer.max_packet_size,
//                             xfer.getTransactionPid(),
//                             xfer.data_buffer,
//                             DEFAULT_TRANSFER_TIMEOUT,
//                         );

//                         log.debug("perform: 'data' transaction returned {any}", .{maybe_in_data_response});

//                         // this should probably report the error through
//                         // the Transfer
//                         const in_data_response = try maybe_in_data_response;

//                         if (in_data_response != xfer.data_buffer.len) {
//                             xfer.transferCompleteTransaction(.data_length_mismatch);
//                         }

//                         xfer.actual_size = in_data_response;

//                         xfer.transferCompleteTransaction(.ok);
//                     },
//                     .handshake => {
//                         log.debug("perform: performing 'status' transaction", .{});

//                         const maybe_status_response = self.transactionOnChannel(
//                             xfer.device_address,
//                             xfer.device_speed,
//                             xfer.endpoint_number,
//                             xfer.endpoint_type,
//                             EndpointDirection.in,
//                             xfer.max_packet_size,
//                             xfer.getTransactionPid(),
//                             &.{},
//                             DEFAULT_TRANSFER_TIMEOUT,
//                         );

//                         log.debug("perform: 'status' transaction returned {any}", .{maybe_status_response});
//                         xfer.transferCompleteTransaction(.ok);
//                     },
//                     .complete => {},
//                 }
//             },
//             TransferType.interrupt => {
//                 // TODO - consider that this might be restarting a
//                 // partially completed transfer
//                 const maybe_response = self.transactionOnChannel(
//                     xfer.device_address,
//                     xfer.device_speed,
//                     xfer.endpoint_number,
//                     xfer.endpoint_type,
//                     EndpointDirection.in,
//                     xfer.max_packet_size,
//                     xfer.getTransactionPid(),
//                     xfer.data_buffer,
//                     DEFAULT_TRANSFER_TIMEOUT,
//                 );

//                 log.debug("perform: 'interrupt' transaction returned {any}", .{maybe_response});
//                 xfer.transferCompleteTransaction(.ok);
//             },
//             else => {
//                 // immediately fail the transfer
//                 xfer.complete(.unsupported_request);
//             },
//         }
//     }
// }

// fn alignedCopy(allocator: Allocator, comptime T: type, v: *const T) !*align(DMA_ALIGNMENT) T {
//     const buffer_size = @sizeOf(T);
//     const aligned_buffer = try allocator.alignedAlloc(u8, DMA_ALIGNMENT, buffer_size);
//     @memcpy(aligned_buffer, std.mem.asBytes(v)[0..buffer_size]);
// }

// This is internal bookkeeping for the host driver. It should not be
// exposed directly to callers.
// const Transaction = struct {
//     host: *Self,
//     deadline: u64 = 0,
//     completed: bool = false,
//     succeeded: bool = false,
//     actual_length: TransferBytes = 0,

//     completion_handler: Channel.CompletionHandler = .{
//         .callbackCompleted = onChannelComplete,
//         .callbackHalted = onChannelHalted,
//     },

//     // Callback invoked by `Channel.channelInterrupt`
//     fn onChannelComplete(handler: *const Channel.CompletionHandler, channel: *Channel, data: []u8) void {
//         log.debug("onChannelComplete for {d}", .{channel.id});

//         var transaction: *Transaction = @constCast(@fieldParentPtr(Transaction, "completion_handler", handler));
//         transaction.actual_length = @truncate(data.len);
//         transaction.completed = true;
//         transaction.succeeded = true;
//     }

//     fn onChannelHalted(handler: *const Channel.CompletionHandler, channel: *Channel) void {
//         var transaction: *Transaction = @constCast(@fieldParentPtr(Transaction, "completion_handler", handler));

//         log.debug("onChannelHalted for {d}, rxstatus = 0x{x:0>8}", .{ channel.id, @as(u32, @bitCast(transaction.host.core_registers.rx_status_read)) });

//         transaction.actual_length = 0;
//         transaction.completed = true;
//     }
// };

// ----------------------------------------------------------------------
// Deferred transfer support
// ----------------------------------------------------------------------

const DeferredTransferArgs = struct {
    host: *Self,
    xfer: *Transfer,
};

pub fn deferTransfer(self: *Self, xfer: *Transfer) !void {
    log.debug("deferring transfer", .{});

    // first time through, allocate a semaphore
    // if the request is deferred more than once, the semaphore is reused
    if (xfer.deferrer_thread_sem == null) {
        xfer.deferrer_thread_sem = try semaphore.create(0);
        errdefer {
            semaphore.free(xfer.deferrer_thread_sem.?);
            xfer.deferrer_thread_sem = null;
        }
    }

    // first time through, allocate a thread.
    // if the request is deferred more than once, the thread is reused
    if (xfer.deferrer_thread == null) {
        var args: DeferredTransferArgs = .{
            .host = self,
            .xfer = xfer,
        };
        xfer.deferrer_thread = try schedule.spawn(deferredTransfer, "usb defer", &args);
    }

    // let the thread progress
    semaphore.signal(xfer.deferrer_thread_sem.?) catch {};
}

fn deferredTransfer(args_ptr: *anyopaque) void {
    const args: *DeferredTransferArgs = @ptrCast(@alignCast(args_ptr));
    const xfer = args.xfer;
    const host = args.host;

    var interval_ms: u32 = 0;

    if (xfer.device.?.speed == UsbSpeed.High) {
        interval_ms = (@as(u32, 1) << @as(u5, @truncate(xfer.endpoint_descriptor.?.interval)) - 1) / USB_UFRAMES_PER_MS;
    } else {
        interval_ms = xfer.endpoint_descriptor.?.interval / USB_FRAMES_PER_MS;
    }

    if (interval_ms == 0) {
        interval_ms = 1;
    }

    while (true) {
        semaphore.wait(xfer.deferrer_thread_sem.?) catch {
            // TODO something
        };

        schedule.sleep(interval_ms) catch {
            // TODO something
        };

        if (host.channelAllocate()) |channel| {
            host.channelStartTransfer(channel, xfer);
        } else |err| {
            log.err("channel allocate error: {any}", .{err});
        }
    }
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
