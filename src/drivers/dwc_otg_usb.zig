const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.dwc_otg_usb);

const root = @import("root");
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
pub const Bus = usb.Bus;
pub const ConfigurationDescriptor = usb.ConfigurationDescriptor;
pub const DeviceAddress = usb.DeviceAddress;
pub const DeviceDescriptor = usb.DeviceDescriptor;
pub const TransactionStage = usb.TransactionStage;
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
pub const HostPeriodicFifo = reg.HostPeriodicFifo;
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
pub const NonPeriodicTxFifoSize = reg.NonPeriodicTxFifoSize;
pub const NonPeriodicTxFifoStatus = reg.NonPeriodicTxFifoStatus;
pub const GeneralCoreConfig = reg.GeneralCoreConfig;
pub const HwConfig2 = reg.HwConfig2;
pub const HwConfig3 = reg.HwConfig3;
pub const HwConfig4 = reg.HwConfig4;
pub const PeriodicTxFifoSize = reg.PeriodicTxFifoSize;
pub const CoreRegisters = reg.CoreRegisters;

// ----------------------------------------------------------------------
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_INTERVAL = 1;
pub const DMA_ALIGNMENT = 64;

// ----------------------------------------------------------------------
// Forty interop table
// ----------------------------------------------------------------------
pub const VTable = struct {
    initialize: *const fn (usb_controller: u64) u64,
    rootPortInitialize: *const fn (usb_controller: u64) u64,
    busInitialize: *const fn (usb_controller: u64) u64,
    deviceGet: *const fn (usb_controller: u64, usb_address: u64) u64,
    dumpStatus: *const fn (usb_controller: u64) void,
};

const HcdChannels = ChannelSet.init("dwc_otg_usb channels", u5, dwc_max_channels);
const UsbAddresses = ChannelSet.init("dwc_otg_usb addresses", u7, std.math.maxInt(u7));

// ----------------------------------------------------------------------
// HCD state
// ----------------------------------------------------------------------
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
channel_assignments: HcdChannels = .{},
channels: [dwc_max_channels]Channel = [_]Channel{.{}} ** dwc_max_channels,
address_assignments: UsbAddresses = .{},
attached_devices: [usb.MAX_ADDRESS]*Device = undefined,

// ----------------------------------------------------------------------
// Interop shims
// ----------------------------------------------------------------------
vtable: VTable = .{
    .initialize = initializeShim,
    .rootPortInitialize = rootPortInitializeShim,
    .busInitialize = busInitializeShim,
    .deviceGet = deviceGetShim,
    .dumpStatus = dumpStatusShim,
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

fn rootPortInitializeShim(usb_controller: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);
    if (self.rootPortInitialize()) |dev| {
        return @intFromPtr(dev);
    } else |err| {
        log.err("USB init root port error: {any}", .{err});
        return 0;
    }
}

fn busInitializeShim(usb_controller: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);
    if (self.busInitialize()) |bus| {
        return @intFromPtr(bus);
    } else |err| {
        log.err("USB bus init error: {any}", .{err});
        return 0;
    }
}

fn deviceGetShim(usb_controller: u64, usb_address: u64) u64 {
    var self: *Self = @ptrFromInt(usb_controller);

    if (usb_address > usb.MAX_ADDRESS) {
        log.err("USB addresses only go up to {d}", .{usb.MAX_ADDRESS});
        return 0;
    }

    if (self.deviceGet(@truncate(usb_address))) |dev| {
        return @intFromPtr(dev);
    } else |err| {
        log.err("USB init root port error: {any}", .{err});
        return 0;
    }
}

fn dumpStatusShim(usb_controller: u64) void {
    var self: *Self = @ptrFromInt(usb_controller);
    self.dumpStatus();
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
        .attached_devices = undefined,
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

// Ugly: this reaches up to the generic layer
pub fn busInitialize(self: *Self) !*Bus {
    const bus: *Bus = try self.allocator.create(Bus);
    try bus.init(self.allocator, self, self.root_port.device);
    return bus;
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

    log.info("DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

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
    log.debug("host init start", .{});

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

    log.debug("host init end", .{});
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

fn rootPortInitialize(self: *Self) !*Device {
    log.debug("root port init start", .{});
    defer log.debug("root port init end", .{});

    return self.root_port.initialize(self);
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
    var my_address: DeviceAddress = try self.claimAddress();

    // 2. tell the actual device what address it should use (on device)
    _ = try self.addressSet(&device.endpoint_0, my_address);
    device.address = my_address;

    // 3. associate the address with the device struct (in memory)
    self.attached_devices[my_address] = device;

    // wait 2 ms for the device to actually change its address
    self.delayMillis(2);
}

// ----------------------------------------------------------------------
// Embedded port interface
// ----------------------------------------------------------------------
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
        try self.deviceConfigure();
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

    fn deviceConfigure(self: *RootPort) !void {
        log.debug("configure device start", .{});
        defer log.debug("configure device end", .{});
        errdefer |err| {
            log.err("configure device error: {any}", .{err});
        }

        const speed = try self.host.getRootPortSpeed();
        log.debug("root port speed: {s}", .{@tagName(speed)});

        self.device = try Device.init(self.allocator);
        self.device.initialize(self.host, speed) catch |err| {
            self.device = undefined;
            return err;
        };
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
// Interrupt handling
// ----------------------------------------------------------------------
fn irqHandle(this: *IrqHandler, _: *InterruptController, _: IrqId) void {
    var self = @fieldParentPtr(Self, "irq_handler", this);

    const intr_status = self.core_registers.core_interrupt_status;

    // check if one of the channels raised the interrupt
    if (intr_status.host_channel_intr == 1) {
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
    if (intr_status.port_intr == 1) {
        const port_status = self.host_registers.port;

        if (port_status.connect_changed == 1) {
            log.debug("irqHandle: Host port connected changed, {d}", .{self.host_registers.port.connect});
            // setting this to 1 clears the interrupt

            // for some reason, when I uncomment this line
            // usb-init-root-port fails in QEMU
            // self.host_registers.port.connect_changed = 1;
        }

        if (port_status.enabled_changed == 1) {
            log.debug("irqHandle: Host port enabled changed, {d}", .{self.host_registers.port.enabled});
            // setting this to 1 clears the interrupt

            // for some reason, when I uncomment this line
            // usb-init-root-port fails in QEMU
            // self.host_registers.port.enabled_changed = 1;
        }

        if (port_status.overcurrent_changed == 1) {
            log.debug("irqHandle: Host port overcurrent changed, {d}", .{self.host_registers.port.overcurrent});
            // setting this to 1 clears the interrupt

            // for some reason, when I uncomment this line
            // usb-init-root-port fails in QEMU
            // self.host_registers.port.overcurrent_changed = 1;
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

// ----------------------------------------------------------------------
// Clock handling
// ----------------------------------------------------------------------

// TODO migrate this to the clock
pub fn deadline(self: *Self, millis: u32) u64 {
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

    transaction.deadline = if (timeout == 0) 0 else self.deadline(timeout);

    try channel.transactionBegin(device, device_speed, endpoint_number, endpoint_type, endpoint_direction, max_packet_size, initial_pid, buffer, &transaction.completion_handler);

    while (self.clock.ticks() < transaction.deadline and !transaction.completed) {}

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

        try channel.waitForState(self.clock, .Idle, 100);

        return 0;
    }
}

// ----------------------------------------------------------------------
// Transfer interface
// ----------------------------------------------------------------------
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

pub const empty_slice: []align(DMA_ALIGNMENT) u8 = &.{};

pub fn controlTransfer(
    self: *Self,
    endpoint: *Endpoint,
    setup: *const SetupPacket,
    data: []align(DMA_ALIGNMENT) u8,
) !TransferBytes {
    const setup_slice: []SetupPacket = try self.allocator.alignedAlloc(SetupPacket, DMA_ALIGNMENT, 1);

    setup_slice[0] = setup.*;

    // TODO this is too simplistic... it will fail if all channels are
    // occupied. A better way would be to enqueue a Request and have a
    // timer- or interrupt-driven dispatcher place transactions on
    // channels as when they are available.
    const device = endpoint.device;

    log.debug("controlTransfer: performing 'setup' transaction with rt = {b}, rq = {d}, mps = {d}", .{ @as(u8, @bitCast(setup.request_type)), setup.request, endpoint.max_packet_size });

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
        4000,
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
        log.debug("controlTransfer: performing 'data' transaction with {any}", .{setup.request_type.transfer_direction});

        const data_direction = switch (setup.request_type.transfer_direction) {
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
            4000,
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
        4000,
    );

    log.debug("controlTransfer: 'status' transaction returned {any}", .{maybe_status_response});

    _ = try maybe_status_response;

    return in_data_response;
}

fn sizeCheck(expected: TransferBytes, actual: TransferBytes) !void {
    if (expected != actual) {
        log.debug("expected {d} bytes, got {d}", .{ expected, actual });
        return Error.InvalidResponse;
    }
}

// ----------------------------------------------------------------------
// Endpoint interactions
// ----------------------------------------------------------------------
fn descriptorQueryUntyped(self: *Self, endpoint: *Endpoint, setup_packet: *const SetupPacket, expected_size: u16) ![]align(DMA_ALIGNMENT) u8 {
    log.debug("descriptor query (type {d}) on device {d} endpoint {d}", .{ setup_packet.value >> 8, endpoint.device.address, endpoint.number });
    var buffer: []align(DMA_ALIGNMENT) u8 = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, setup_packet.data_size);

    const returned = try self.controlTransfer(endpoint, setup_packet, buffer);

    try sizeCheck(expected_size, returned);

    return buffer;
}

pub fn descriptorQuery(self: *Self, endpoint: *Endpoint, setup_packet: *const SetupPacket, comptime T: type) !T {
    const expected_size: u16 = @sizeOf(T);
    const buffer = try self.descriptorQueryUntyped(endpoint, setup_packet, @sizeOf(T));
    defer self.allocator.free(buffer);

    const result: *T = std.mem.bytesAsValue(T, buffer[0..expected_size]);
    return result.*;
}

pub fn deviceDescriptorQuery(self: *Self, endpoint: *Endpoint, descriptor_index: usb.DescriptorIndex, lang_id: u16) !DeviceDescriptor {
    const expected_size = @sizeOf(DeviceDescriptor);
    const setup = usb.setupDescriptorQuery(.device, descriptor_index, lang_id, expected_size);

    return self.descriptorQuery(endpoint, &setup, DeviceDescriptor);
}

pub fn configurationDescriptorQuery(self: *Self, endpoint: *Endpoint, configuration_index: usb.DescriptorIndex) !ConfigurationDescriptor {
    const expected_size = @sizeOf(ConfigurationDescriptor);
    const setup = usb.setupDescriptorQuery(.configuration, configuration_index, 0, expected_size);

    return self.descriptorQuery(endpoint, &setup, ConfigurationDescriptor);
}

// This returns the entire configuration hierarchy, including all
// interfaces and endpoints. In order to construct a buffer big enough
// you should first use configurationDescriptorQuery and allocate
// space according to the `total_length` field.
pub fn configurationTreeGet(self: *Self, endpoint: *Endpoint, configuration_index: usb.DescriptorIndex, expected_size: u16) ![]align(DMA_ALIGNMENT) u8 {
    log.info("configurationTreeGet: looking for {d} bytes from configuration {d}", .{ expected_size, configuration_index });

    const setup = usb.setupDescriptorQuery(.configuration, configuration_index, 0, expected_size);
    // The buffer will be populated, but we don't need the
    // ConfigurationDescriptor constructed from it.
    return self.descriptorQueryUntyped(endpoint, &setup, expected_size);
}

pub fn stringDescriptorQuery(self: *Self, endpoint: *Endpoint, index: StringIndex, language: LangID) !StringDescriptor {
    const expected_size = @sizeOf(StringDescriptor);
    const setup = usb.setupDescriptorQuery(.string, index, @intFromEnum(language), expected_size);

    return self.descriptorQuery(endpoint, &setup, StringDescriptor);
}

pub fn stringQuery(self: *Self, endpoint: *Endpoint, index: StringIndex, language: LangID) ![]u8 {
    const desc = try self.stringDescriptorQuery(endpoint, index, language);
    return desc.asSlice(self.allocator);
}

pub fn addressSet(self: *Self, endpoint: *Endpoint, address: DeviceAddress) !u19 {
    log.debug("set address {d} on endpoint {d}", .{ address, endpoint.number });

    const setup = usb.setupSetAddress(address);
    const ret = self.controlTransfer(endpoint, &setup, empty_slice);

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
    speed: usb.UsbSpeed,
    address: usb.DeviceAddress,
    endpoint_0: Endpoint,
    device_descriptor: usb.DeviceDescriptor,
    configuration_descriptor: usb.ConfigurationDescriptor,
    interface_descriptor: usb.InterfaceDescriptor,
    manufacturer: []u8,
    product_name: []u8,
    configuration: []u8,
    interface: []u8,

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
            .interface_descriptor = undefined,
            .manufacturer = "",
            .product_name = "",
            .configuration = "",
            .interface = "",
        };

        return device;
    }

    pub fn initialize(self: *Device, host: *Self, speed: usb.UsbSpeed) !void {
        self.host = host;
        self.speed = speed;

        self.device_descriptor = try host.deviceDescriptorQuery(&self.endpoint_0, usb.DEFAULT_DESCRIPTOR_INDEX, 0);
        self.device_descriptor.dump();

        try host.assignAddress(self);

        // self.determineProductName() catch |err| {
        //     log.warn("Could not read manufacturer and product name: {any}", .{err});
        // };

        // if (self.device_descriptor.configuration_count >= 1) {
        //     self.configuration_descriptor = try host.configurationDescriptorQuery(&self.endpoint_0, 0);

        //     if (self.configuration_descriptor.configuration > 0) {
        //         self.determineConfiguration() catch |err| {
        //             log.warn("Could not read configuration value for index {d}: {any}", .{ self.configuration_descriptor.configuration, err });
        //         };
        //     }

        //     self.configuration_descriptor.dump(self.configuration);

        //     if (self.configuration_descriptor.interface_count >= 1) {
        //         const config_tree_size = self.configuration_descriptor.total_length;
        //         const buffer = try self.host.configurationTreeGet(&self.endpoint_0, 0, config_tree_size);
        //         root.debug.kernelMessage(buffer);
        //         //                self.allocator.free(buffer);

        //         // self.interface_descriptor = try host.interfaceDescriptorQuery(&self.endpoint_0, 0);

        //         // if (self.interface_descriptor.interface_string > 0) {
        //         //     self.determineInterface() catch |err| {
        //         //         log.warn("Could not read interface name for index {d}: {any}", .{ self.interface_descriptor.interface_string, err });
        //         //     };
        //         // }

        //         // self.interface_descriptor.dump(self.interface);
        //     }
        // }
    }

    fn determineProductName(self: *Device) !void {
        const mfg = try self.host.stringDescriptorQuery(&self.endpoint_0, self.device_descriptor.manufacturer_name, LangID.en_US);
        self.manufacturer = try mfg.asSlice(self.allocator);

        const prod = try self.host.stringDescriptorQuery(&self.endpoint_0, self.device_descriptor.product_name, LangID.en_US);
        self.product_name = try prod.asSlice(self.allocator);
    }

    fn determineConfiguration(self: *Device) !void {
        const val = try self.host.stringDescriptorQuery(&self.endpoint_0, self.configuration_descriptor.configuration, LangID.en_US);
        self.configuration = try val.asSlice(self.allocator);
    }

    fn determineInterface(self: *Device) !void {
        const val = try self.host.stringDescriptorQuery(&self.endpoint_0, self.interface_descriptor.interface_string, LangID.en_US);
        self.interface = try val.asSlice(self.allocator);
    }
};
