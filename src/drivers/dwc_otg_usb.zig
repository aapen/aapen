const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;

const log = std.log.scoped(.dwc_otg_usb);

const root = @import("root");
const InterruptController = root.HAL.InterruptController;
const IrqId = InterruptController.IrqId;
const IrqHandlerFn = InterruptController.IrqHandlerFn;
const IrqHandler = InterruptController.IrqHandler;

const Forth = @import("../forty/forth.zig").Forth;
const auto = @import("../forty/auto.zig");

const time = @import("../time.zig");

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
pub const Bus = usb.Bus;
pub const ConfigurationDescriptor = usb.ConfigurationDescriptor;
pub const DeviceAddress = usb.DeviceAddress;
pub const DeviceConfiguration = usb.DeviceConfiguration;
pub const DeviceDescriptor = usb.DeviceDescriptor;
pub const EndpointDescriptor = usb.EndpointDescriptor;
pub const EndpointDirection = usb.EndpointDirection;
pub const EndpointNumber = usb.EndpointNumber;
pub const EndpointType = usb.EndpointType;
pub const Hub = usb.Hub;
pub const InterfaceDescriptor = usb.InterfaceDescriptor;
pub const LangID = usb.LangID;
pub const PacketSize = usb.PacketSize;
pub const PID = usb.PID2;
pub const SetupPacket = usb.SetupPacket;
pub const StringDescriptor = usb.StringDescriptor;
pub const StringIndex = usb.StringIndex;
pub const Transfer = usb.Transfer;
pub const TransferBytes = usb.TransferBytes;
pub const TransferFactory = usb.TransferFactory;
pub const UsbSpeed = usb.UsbSpeed;

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

const dwc_max_channels = 16;

const PendingTransfers = DoublyLinkedList(Transfer);

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
    NoChannelAvailable,
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
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_INTERVAL = 1;
pub const DMA_ALIGNMENT = 64;

// ----------------------------------------------------------------------
// HCD state
// ----------------------------------------------------------------------
const HcdChannels = ChannelSet.init("dwc_otg_usb channels", u5, dwc_max_channels);
const UsbAddresses = ChannelSet.init("dwc_otg_usb addresses", u7, std.math.maxInt(u7));

allocator: Allocator,
core_registers: *volatile CoreRegisters,
host_registers: *volatile HostRegisters,
power_and_clock_control: *volatile PowerAndClock,
all_channel_intmask_lock: Spinlock,
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
address_assignments: UsbAddresses = .{},
attached_devices: [usb.MAX_ADDRESS]*Device = undefined,
pending_transfers: PendingTransfers = undefined,

// Ideas for improving this:
// - reserve an aligned buffer for each channel to use. that avoids
//   dynamic allocation in the inner loop
// - keep a top-level array of Hubs
// - keep a top-level array of HIDs

// ----------------------------------------------------------------------
// Forty interop
// ----------------------------------------------------------------------

pub fn defineModule(forth: *Forth) !void {
    try auto.defineNamespace(Self, .{
        .{ "initialize", "usb-init-hcd" },
    }, forth);
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
        .all_channel_intmask_lock = Spinlock.init("all channels interrupt mask", true),
        .intc = intc,
        .irq_id = irq_id,
        .translations = translations,
        .power_controller = power,
        .num_host_channels = 0,
        .attached_devices = undefined,
        .pending_transfers = .{},
    };

    for (0..dwc_max_channels) |chid| {
        const channel_registers: *volatile ChannelRegisters = @ptrFromInt(register_base + 0x500 + (@sizeOf(ChannelRegisters) * chid));
        self.channels[chid].init(@truncate(chid), channel_registers);
    }

    // address 0 needs to be marked as "claimed" so we don't assign it
    // to any actual device
    _ = try self.address_assignments.allocate();

    return self;
}

pub fn initialize(self: *Self) !void {
    try self.powerOn();
    try self.verifyHostControllerDevice();
    try self.resetSoft();
    try self.initializeControllerCore();
    try self.initializeInterrupts();
}

fn powerOn(self: *Self) !void {
    const power_result = try self.power_controller.powerOn(.usb_hcd);

    if (power_result != .power_on) {
        log.err("Failed to power on USB device: {any}", .{power_result});
        return Error.PowerFailure;
    }

    // wait a bit for power to settle
    time.delayMillis(10);
}

fn powerOff(self: *Self) !void {
    const power_result = try self.power_controller.powerOff(.usb_hcd);

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

    log.info("{d} words of RAM available for dynamic FIFOs", .{@as(u32, @bitCast(self.core_registers.hardware_config_3)) >> 16});
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
// Device registry
// ----------------------------------------------------------------------
pub fn deviceGet(self: *Self, address: DeviceAddress) !*Device {
    if (self.address_assignments.isAllocated(address)) {
        return self.attached_devices[address];
    } else {
        return Error.NoDevice;
    }
}

fn claimAddress(self: *Self) !DeviceAddress {
    return self.address_assignments.allocate();
}

pub fn assignAddress(self: *Self, device: *Device) !void {
    // assigning an address is a 3 step process

    // TODO - if the addressSet fails, should release the address assignment

    // 1. reserve an address (in memory)
    const my_address: DeviceAddress = try self.claimAddress();

    // 2. tell the actual device what address it should use (on device)
    _ = try self.addressSet(&device.endpoint_0, my_address);
    device.address = my_address;

    // 3. associate the address with the device struct (in memory)
    self.attached_devices[my_address] = device;

    // wait 2 ms for the device to actually change its address
    time.delayMillis(2);
}

// ----------------------------------------------------------------------
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    var self = @fieldParentPtr(Self, "irq_handler", this);

    const intr_status = self.core_registers.core_interrupt_status;

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel == 1) {
        const all_intrs = self.host_registers.all_channel_interrupts;
        //        self.host_registers.all_channel_interrupts = all_intrs;

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

    // check if the host port raised the interrupt
    if (intr_status.port == 1) {
        const port_status = self.host_registers.port;

        if (port_status.connect_changed == 1) {
            log.debug("irqHandle: Host port connected changed, {d}", .{self.host_registers.port.connect});
            // setting this to 1 clears the interrupt
            self.host_registers.port.connect_changed = 1;
        }

        if (port_status.enabled_changed == 1) {
            log.debug("irqHandle: Host port enabled changed, {d}", .{self.host_registers.port.enabled});
            // setting this to 1 clears the interrupt
            self.host_registers.port.enabled_changed = 1;
        }

        if (port_status.overcurrent_changed == 1) {
            log.debug("irqHandle: Host port overcurrent changed, {d}", .{self.host_registers.port.overcurrent});
            // setting this to 1 clears the interrupt
            self.host_registers.port.overcurrent_changed = 1;
        }
    }

    // clear the interrupt bits
    self.core_registers.core_interrupt_status = intr_status;
}

pub fn getRootPortSpeed(self: *Self) !usb.UsbSpeed {
    return switch (self.host_registers.port.speed) {
        .high => .High,
        .full => .Full,
        .low => .Low,
        else => Error.ConfigurationError,
    };
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
    //    dumpRegister("periodic_tx_fifo_status", @bitCast(self.host_registers.periodic_tx_fifo_status));
    dumpRegisterPair("all_channel_interrupts", @bitCast(self.host_registers.all_channel_interrupts), "all_channel_interrupts_mask", @bitCast(self.host_registers.all_channel_interrupts_mask));
    //    dumpRegister("frame_list_base_addr", @bitCast(self.host_registers.frame_list_base_addr));
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
        .actual_length = 0,
    };

    log.debug("Acquiring channel", .{});

    var channel = try self.channelAllocate();
    defer self.channelFree(channel);

    log.debug("Received channel {d}", .{channel.id});

    self.channelInterruptEnable(channel.id);
    defer self.channelInterruptDisable(channel.id);

    transaction.deadline = if (timeout == 0) 0 else time.deadlineMillis(timeout);

    try channel.transactionBegin(device, device_speed, endpoint_number, endpoint_type, endpoint_direction, max_packet_size, initial_pid, buffer, &transaction.completion_handler);

    while (time.ticks() < transaction.deadline and !transaction.completed) {}

    // wait for transaction.completed to be true, or deadline elapsed.
    if (transaction.completed) {
        if (transaction.succeeded) {
            log.debug("Transaction succeeded", .{});
            return transaction.actual_length;
        } else {
            log.debug("Transaction halted", .{});
            return 0;
        }
    } else {
        log.warn("Transaction timed out on channel {d}", .{channel.id});
        // if timeout, abort the transaction
        channel.channelAbort();

        try channel.waitForState(.Idle, 100);

        return 0;
    }
}

// ----------------------------------------------------------------------
// Transfer interface - high level
// ----------------------------------------------------------------------
fn pendingTransferCreate(self: *Self, xfer: *Transfer) !*PendingTransfers.Node {
    const node: *PendingTransfers.Node = try self.allocator.create(PendingTransfers.Node);
    node.data = xfer;
    return node;
}

fn pendingTransferDestroy(self: *Self, node: *PendingTransfers.Node) void {
    self.allocator.destroy(node);
}

pub fn perform(self: *Self, xfer: *Transfer) !void {
    // put the transfer in the pending_transfers list.
    self.pending_transfers.append(try self.pendingTransferCreate(xfer));

    // kick the scheduler (what scheduler ?!)

    // on timer interrupt, check for any pending transfer and see if
    // there's a channel available.
    // hand the transfer off to the channel.

    // This driver-level routine assumes that a higher-level caller
    // has already checked the Transfer's consistency against USB
    // specifications

    // TODO this is too simplistic... it will fail if all channels are
    // occupied. A better way would be to enqueue a Request and have a
    // timer- or interrupt-driven dispatcher place transactions on
    // channels as when they are available.

    // old implementation below here.
    while (xfer.state != .complete) {
        switch (xfer.transfer_type) {
            .control => {
                switch (xfer.state) {
                    .token => {
                        const aligned_buffer = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(SetupPacket));
                        defer self.allocator.free(aligned_buffer);

                        @memcpy(aligned_buffer, std.mem.asBytes(&xfer.setup));

                        log.debug("perform: performing 'setup' transaction with rt = {b}, rq = {d}, mps = {d}", .{ @as(u8, @bitCast(xfer.setup.request_type)), xfer.setup.request, xfer.max_packet_size });

                        const maybe_setup_response = self.transactionOnChannel(
                            xfer.device_address,
                            xfer.device_speed,
                            xfer.endpoint_number,
                            xfer.endpoint_type,
                            .out,
                            xfer.max_packet_size,
                            xfer.getTransactionPid(),
                            aligned_buffer,
                            100,
                        );

                        if (maybe_setup_response) |bytes| {
                            if (bytes == @sizeOf(SetupPacket)) {
                                xfer.transferCompleteTransaction(.ok);
                            } else {
                                xfer.transferCompleteTransaction(.data_length_mismatch);
                            }
                        } else |_| {
                            xfer.transferCompleteTransaction(.failed);
                        }
                    },
                    .data => {
                        log.debug("perform: performing 'data' transaction with {any}", .{xfer.setup.request_type.transfer_direction});

                        const data_direction = switch (xfer.setup.request_type.transfer_direction) {
                            .host_to_device => EndpointDirection.out,
                            .device_to_host => EndpointDirection.in,
                        };

                        const maybe_in_data_response = self.transactionOnChannel(
                            xfer.device_address,
                            xfer.device_speed,
                            xfer.endpoint_number,
                            xfer.endpoint_type,
                            data_direction,
                            xfer.max_packet_size,
                            xfer.getTransactionPid(),
                            xfer.data_buffer,
                            100,
                        );

                        log.debug("perform: 'data' transaction returned {any}", .{maybe_in_data_response});

                        // this should probably report the error through
                        // the Transfer
                        var in_data_response = try maybe_in_data_response;

                        if (in_data_response != xfer.data_buffer.len) {
                            xfer.transferCompleteTransaction(.data_length_mismatch);
                        }

                        xfer.actual_size = in_data_response;

                        xfer.transferCompleteTransaction(.ok);
                    },
                    .handshake => {
                        log.debug("perform: performing 'status' transaction", .{});

                        const maybe_status_response = self.transactionOnChannel(
                            xfer.device_address,
                            xfer.device_speed,
                            xfer.endpoint_number,
                            xfer.endpoint_type,
                            .in,
                            xfer.max_packet_size,
                            xfer.getTransactionPid(),
                            &.{},
                            100,
                        );

                        log.debug("perform: 'status' transaction returned {any}", .{maybe_status_response});
                        xfer.transferCompleteTransaction(.ok);
                    },
                    .complete => {},
                }
            },
            else => {
                // immediately fail the transfer
                xfer.complete(.unsupported_request);
            },
        }
    }
}

fn alignedCopy(allocator: Allocator, comptime T: type, v: *const T) !*align(DMA_ALIGNMENT) T {
    const buffer_size = @sizeOf(T);
    const aligned_buffer = try allocator.alignedAlloc(u8, DMA_ALIGNMENT, buffer_size);
    @memcpy(aligned_buffer, std.mem.asBytes(v)[0..buffer_size]);
}

// This is internal bookkeeping for the host driver. It should not be
// exposed directly to callers.
const Transaction = struct {
    host: *Self,
    deadline: u64 = 0,
    completed: bool = false,
    succeeded: bool = false,
    actual_length: TransferBytes = 0,

    completion_handler: Channel.CompletionHandler = .{
        .callbackCompleted = onChannelComplete,
        .callbackHalted = onChannelHalted,
    },

    // Callback invoked by `Channel.channelInterrupt`
    fn onChannelComplete(handler: *const Channel.CompletionHandler, channel: *Channel, data: []u8) void {
        log.debug("onChannelComplete for {d}", .{channel.id});

        var transaction: *Transaction = @constCast(@fieldParentPtr(Transaction, "completion_handler", handler));
        transaction.actual_length = @truncate(data.len);
        transaction.completed = true;
        transaction.succeeded = true;
    }

    fn onChannelHalted(handler: *const Channel.CompletionHandler, channel: *Channel) void {
        var transaction: *Transaction = @constCast(@fieldParentPtr(Transaction, "completion_handler", handler));

        log.debug("onChannelHalted for {d}, rxstatus = 0x{x:0>8}", .{ channel.id, @as(u32, @bitCast(transaction.host.core_registers.rx_status_read)) });

        transaction.actual_length = 0;
        transaction.completed = true;
    }
};

pub fn addressSet(self: *Self, endpoint: *Endpoint, address: DeviceAddress) !u19 {
    log.debug("set address {d} on endpoint {d}", .{ address, endpoint.number });

    var xfer = TransferFactory.initSetAddressTransfer(address);
    xfer.endpoint_number = endpoint.number;

    try self.perform(&xfer);

    log.debug("set address {d} on endpoint {d} returned {any}", .{ address, endpoint.number, xfer.actual_size });

    return xfer.actual_size;
}

// ----------------------------------------------------------------------
// USB Device Model
// ----------------------------------------------------------------------
const Function = struct {};

const Endpoint = struct {
    device: *Device,
    number: EndpointNumber,
    type: usb.EndpointType = .Control,
    direction: EndpointDirection = .out,
    max_packet_size: u11 = usb.DEFAULT_MAX_PACKET_SIZE,
};

pub const Device = struct {
    pub const MAX_INTERFACES: usize = 8;
    pub const MAX_ENDPOINTS: usize = 8;

    allocator: Allocator,
    host: *Self,
    speed: usb.UsbSpeed,
    address: usb.DeviceAddress,
    endpoint_0: Endpoint,
    device_descriptor: DeviceDescriptor,
    configuration_descriptor: ConfigurationDescriptor,
    configuration: *DeviceConfiguration,
    manufacturer: []u8,
    product_name: []u8,

    pub fn init(allocator: Allocator) !*Device {
        var device = try allocator.create(Device);

        device.* = .{
            .allocator = allocator,
            .host = undefined,
            .speed = undefined,
            .address = usb.DEFAULT_ADDRESS,
            .endpoint_0 = .{ .number = 0, .device = device },
            .device_descriptor = undefined,
            .configuration_descriptor = undefined,
            .manufacturer = "",
            .product_name = "",
            .configuration = undefined,
        };

        return device;
    }

    pub fn initialize(self: *Device, host: *Self, speed: usb.UsbSpeed) !void {
        self.host = host;
        self.speed = speed;

        var xfer = TransferFactory.initDeviceDescriptorTransfer(usb.DEFAULT_DESCRIPTOR_INDEX, 0, std.mem.asBytes(&self.device_descriptor));

        xfer.device_address = 0;
        xfer.endpoint_number = 0;

        try host.perform(&xfer);

        if (xfer.status != .ok) {
            return Error.InvalidResponse;
        }

        self.device_descriptor.dump();

        try host.assignAddress(self);

        if (self.getProductName()) {
            log.info("Product: '{s}'", .{self.product_name});
        } else |err| {
            log.warn("Could not read manufacturer and product name: {any}", .{err});
        }

        if (self.getManufacturer()) {
            log.info("Manufacturer: '{s}'", .{self.manufacturer});
        } else |err| {
            log.warn("Could not read manufacturer and product name: {any}", .{err});
        }

        if (self.device_descriptor.configuration_count >= 1) {
            if (self.fetchConfiguration()) {
                self.configuration.dump();
            } else |err| {
                log.warn("Could not read configuration descriptor: {any}", .{err});
            }
        }
    }

    fn fetchConfiguration(self: *Device) !void {
        // First fetch just the configuration descriptor (it's the
        // root of the config tree)
        var xfer = TransferFactory.initConfigurationDescriptorTransfer(0, std.mem.asBytes(&self.configuration_descriptor));
        xfer.device_address = self.address;

        try self.host.perform(&xfer);

        if (xfer.status != .ok) {
            return Error.InvalidResponse;
        }

        // The header of the configuration descriptor tells us how
        // much space the whole config tree requires
        const buffer_size = self.configuration_descriptor.total_length;
        var buffer = try self.allocator.alloc(u8, buffer_size);
        defer self.allocator.free(buffer);

        log.info("Configuration {d} reports that it has {d} bytes to tell us about", .{ 0, buffer_size });

        xfer = TransferFactory.initConfigurationDescriptorTransfer(0, buffer);
        xfer.device_address = self.address;

        try self.host.perform(&xfer);

        if (xfer.status != .ok) {
            log.debug("fetchConfiguration: read of whole configuration tree failed: {any}", .{xfer.status});
            return Error.InvalidResponse;
        }

        if (xfer.actual_size != buffer_size) {
            log.debug("fetchConfiguration: read of whole configuration tree returns incorrect number of bytes: {d}", .{xfer.actual_size});
            return Error.DataLengthMismatch;
        }

        root.debug.sliceDump(buffer);

        if (DeviceConfiguration.initFromBytes(self.allocator, buffer)) |conf| {
            self.configuration = conf;
        } else |err| {
            log.err("fetchConfiguration: cannot parse device configuration tree: {any}", .{err});
        }
    }

    fn getManufacturer(self: *Device) !void {
        self.manufacturer = try self.getString(self.device_descriptor.manufacturer_name, LangID.en_US);
    }

    fn getProductName(self: *Device) !void {
        self.product_name = try self.getString(self.device_descriptor.product_name, LangID.en_US);
    }

    fn getConfiguration(self: *Device) !void {
        self.configuration = try self.getString(self.configuration_descriptor.configuration, LangID.en_US);
    }

    fn getString(self: *Device, index: u8, lang: LangID) ![]u8 {
        const buffer_size = @sizeOf(StringDescriptor);
        var buffer: [buffer_size]u8 align(2) = undefined;

        var xfer = TransferFactory.initStringDescriptorTransfer(index, lang, &buffer);
        xfer.device_address = self.address;

        try self.host.perform(&xfer);

        const configuration: *StringDescriptor = std.mem.bytesAsValue(StringDescriptor, buffer[0..buffer_size]);
        return try configuration.asSlice(self.allocator);
    }
};
