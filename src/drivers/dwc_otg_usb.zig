const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const kprint = root.kprint;

const local_interrupt_controller = @import("arm_local_interrupt_controller.zig");
const LocalInterruptController = local_interrupt_controller.LocalInterruptController;

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

const usb = @import("../usb.zig");
const Address = usb.Address;
const ConfigurationDescriptor = usb.ConfigurationDescriptor;
const DEFAULT_ADDRESS = usb.DEFAULT_ADDRESS;
const DEFAULT_MAX_PACKET_SIZE = usb.DEFAULT_MAX_PACKET_SIZE;
const DeviceDescriptor = usb.DeviceDescriptor;
const EndpointType = usb.EndpointType;
const RequestType = usb.RequestType;
const UsbSpeed = usb.UsbSpeed;

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

const dwc_max_channels = 16;

// ----------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------

pub const Error = error{
    IncorrectDevice,
    PowerFailure,
    ConfigurationError,
};

const VendorId = packed struct {
    device_minor_rev: u12 = 0,
    device_series: u4 = 0,
    device_vendor_id: u16 = 0, // (maybe this is the vendor id?)
};

// ----------------------------------------------------------------------
// Channel Registers
// ----------------------------------------------------------------------

const ChannelCharacteristics = packed struct {
    max_packet_size: u11, // 0..10
    endpoint_number: u4, // 11..14
    endpoint_direction: u1, // 15
    _reserved_16: u1, // 16
    low_speed_device: u1, // 17
    endpoint_type: enum(u2) {
        control = 0,
        isochronous = 1,
        bulk = 2,
        interrupt = 3,
    }, // 18..19
    packets_per_frame: u2, // 20..21
    device_address: u7, // 22..28
    odd_frame: u1, // 29
    disable: u1, // 30
    enable: u1, // 31
};

const ChannelSplitControl = packed struct {
    port_address: u7, // 0 .. 6
    hub_address: u7, // 7..13
    transaction_position: u2, // 14..15
    complete_split: u1, // 16
    _reserved_17_30: u14, // 17..30
    split_enable: u1, // 31
};

const ChannelInterrupt = packed struct {
    transfer_completed: u1, // 0
    halted: u1, // 1
    ahb_error: u1, // 2
    stall_response_received: u1, // 3
    nak_response_received: u1, // 4
    ack_response_received: u1, // 5
    nyet_response_received: u1, // 6
    transaction_error: u1, // 7
    babble_error: u1, // 8
    frame_overrun: u1, // 9
    data_toggle_error: u1, // 10
    buffer_not_available: u1, // 11
    excess_transaction_error: u1, // 12
    frame_list_rollover: u1, // 13
    _reserved_18_31: u18, // 14..31
};

const ChannelTransferSize = packed struct {
    transfer_size_bytes: u19, // 0..18
    transfer_size_packets: u10, // 19..28
    packet_id: u2, // 29..30
    do_ping: u1, // 31
};

const HostChannelRegisters = extern struct {
    host_channel_character: ChannelCharacteristics, // 0x00
    host_channel_split_control: ChannelSplitControl, // 0x04
    host_channel_int: ChannelInterrupt, // 0x08
    host_channel_int_mask: ChannelInterrupt, // 0x0c
    host_channel_txfer_size: ChannelTransferSize, // 0x10
    host_channel_dma_addr: u32 = 0, // 0x14
    _reserved: u32 = 0, // 0x18
    host_channel_dma_buf: u32 = 0, // 0x1c
};

// ----------------------------------------------------------------------
// Host Registers
// ----------------------------------------------------------------------

const HostConfig = packed struct {
    fsls_pclk_sel: enum(u2) {
        sel_30_60_mhz = 0,
        sel_48_mhz = 1,
        sel_6_mhz = 2,
        undefined = 3,
    }, // 0..1
    fs_ls_support_only: u1, // 2
    _unknown_0: u4, // 3..6
    enable_32khz: u1, // 7
    resume_valid: u8, // 8 .. 15
    _unknown_1: u7, // 16..22
    desc_dma: u1, // 23
    frame_list_entries: enum(u2) {
        list_entries_8 = 0,
        list_entries_16 = 1,
        list_entries_32 = 2,
        list_entries_64 = 3,
    }, // 24..25
    per_sched_enable: u1, //26
    _unknown_2: u4, // 27..30
    mode_ch_tim_en: u1, // 31

};

const HostFrames = packed struct {
    number: u16,
    remaining: u16,
};

const HostPort = packed struct {
    connect: u1, // 0
    connect_changed: u1, // 1
    enabled: u1, // 2
    enabled_changed: u1, // 3
    overcurrent: u1, // 4
    overcurrent_changed: u1, // 5
    status_resume: u1, // 6
    suspended: u1, // 7
    reset: u1, // 8
    _reserved_9: u1, // 9
    line_status: u2, // 10..11
    power: u1, // 12
    test_control: u4, // 13..16
    speed: enum(u2) {
        high = 0,
        full = 1,
        low = 2,
        undefined = 3,
    }, // 17..18
    _reserved_19_32: u13, // 19..31
};

const HostRegisters = extern struct {
    config: HostConfig, // 0x00
    frame_interval: u32 = 0, // 0x04
    frame_num: HostFrames, // 0x08
    _reserved_0x0c: u32 = 0, // 0x0c
    periodic_tx_fifo_status: u32 = 0, // 0x10
    all_channel_interrupts: u32 = 0, // 0x14
    all_channel_interrupts_mask: u32 = 0, // 0x18
    frame_list_base_addr: u32 = 0, // 0x1c
    _unused_padding_1: [8]u32, // 0x20 .. 0x3c
    port: HostPort, // 0x40
};

// ----------------------------------------------------------------------
// Core Registers
// ----------------------------------------------------------------------

const OtgControl = packed struct {
    _unknown: u9 = 0,
    hnp_enable: u1 = 0,
    _unknown_2: u22 = 0,
};

const AhbConfig = packed struct {
    global_interrupt_mask: u1, // 0
    max_axi_burst: u2, // 1..2
    _unknown_0: u1 = 0, // 3
    wait_axi_writes: u1, // 4
    dma_enable: u1, // 5
    _unknown_1: u17, // 6..22
    ahb_single: u1, // 23
    _unknown_2: u8, // 24 .. 31
};

const UsbConfig = packed struct {
    toutcal: u3, // 0..3
    phy_if: u1, // 3
    ulpi_utmi_sel: u1, // 4
    fs_intf: u1, // 5
    phy_sel: u1, // 6
    ddr_sel: u1, // 7
    srp_capable: u1, // 8
    hnp_capable: u1, // 9
    usb_trdtim: u4, // 10..13
    _reserved_14: u1, // 14
    phy_low_pwr_clk_sel: u1, // 15
    otg_utmi_fs_sel: u1, // 16
    ulpi_fsls: u1, // 17
    ulpi_auto_res: u1, // 18
    ulpi_clk_sus_m: u1, // 19
    ulpi_ext_vbus_drv: u1, // 20
    ulpi_int_vbus_indicator: u1, // 21
    term_sel_dl_pulse: u1, // 22
    indicator_complement: u1, //23
    indicator_passthrough: u1, // 24
    ulpi_int_prot_dis: u1, // 25
    ic_usb_cap: u1, // 26
    ic_traffic_pull_remove: u1, // 27
    tx_end_delay: u1, // 28
    force_host_mode: u1, // 29
    force_device_mode: u1, // 30
    _reserved_31: u1, // 31
};

const Reset = packed struct {
    soft_reset: u1, // 0
    _unknown_0: u3, // 1..3
    rx_fifo_flush: u1, // 4
    tx_fifo_flush: u1, // 5
    tx_fifo_num: u5, // 6..11
    _unknown_1: u20, // 12..30
    ahb_idle: u1, // 31
};

const InterruptStatus = packed struct {
    _unknown_0: u3, // 0..2
    sof_intr: u1, // 3
    _unknown_1: u20, // 4..23
    port_intr: u1, // 24
    host_channel_intr: u1, // 25
    _unknown_2: u3, // 26..28
    disconnect: u1, // 29
    _unknown_3: u2, // 30..31
};

const InterruptMask = packed struct {
    _unknown_0: u1, // 0
    mode_mismatch: u1, // 1
    _unknown_1: u1, // 2
    sof_intr: u1, // 3
    rx_sts_q_lvl: u1, // 4
    _unknown_2: u6, // 5..10
    usb_suspend: u1, // 11
    _unknown_3: u12, // 12..23
    port_intr: u1, // 24
    host_channel_intr: u1, // 25
    _unknown_4: u2, // 26..27
    con_id_sts_chng: u1, // 28
    disconnect: u1, // 29
    sess_req_intr: u1, // 30
    wakeup_intr: u1, // 31

};

const RxStatus = packed struct {
    channel_number: u4, // 0..3
    byte_count: u12, // 4..15
    packet_status: u4, // 17..20
    _unknown_0: u12, // 21..31
};

const HwConfig2 = packed struct {
    operating_mode: enum(u3) {
        hnp_srp_capable_otg = 0,
        srp_only_capable_otg = 1,
        no_hnp_src_capable_otg = 2,
        srp_capable_device = 3,
        no_srp_capable_device = 4,
        srp_capable_host = 5,
        no_srp_capable_host = 6,
        undefined = 7,
    }, // 0..2
    architecture: enum(u2) {
        slave_only = 0,
        ext_dma = 1,
        int_dma = 2,
        undefined = 3,
    }, // 3..4
    point_to_point: u1, // 5
    hs_phy_type: enum(u2) {
        not_supported = 0,
        utmi = 1,
        ulpi = 2,
        utmi_ulpi = 3,
    }, // 6..8
    fs_phy_type: enum(u2) {
        unknown_0 = 0,
        dedicated = 1,
        unknown_2 = 2,
        unknown_3 = 3,
    }, // 8..9
    num_device_endpoints: u4, // 10..13
    num_host_channels: u4, // 14..17
    periodic_endpoint_supported: u1, // 18
    dynamic_fifo: u1, // 19
    multi_proc_int: u1, // 20
    _reserved_21: u1, // 21
    non_periodic_tx_queue_depth: u2, // 22..23
    host_periodic_tx_queue_depth: u2, //24..25
    device_token_queue_depth: u5, // 26..30
    otg_enable_ic_usb: u1, // 31
};

const HwConfig3 = packed struct {
    _unknown: u16, // 0..15
    dynamic_fifo_total_size: u16, // 16..31
};

const HwConfig4 = packed struct {
    _unknown_0: u25, // 0..24
    ded_fifo_enable: u1, // 25
    num_in_eps: u4, // 26..29
    _unknown_1: u2, // 30..31
};

const CoreRegisters = extern struct {
    otg_control: OtgControl, // 0x00
    otg_interrupt: u32 = 0, // 0x04
    ahb_config: AhbConfig, // 0x08
    usb_config: UsbConfig, // 0x0c
    reset: Reset, // 0x10
    interrupt_status: InterruptStatus, // 0x14
    interrupt_mask: InterruptMask, // 0x18
    rx_status_read: RxStatus, // 0x1c
    rs_status_pop: RxStatus, // 0x20
    rx_fifo_size: u32 = 0, // 0x24
    nonperiodic_tx_fifo_size: u32 = 0, // 0x28
    nonperiodic_tx_status: u32 = 0, // 0x2c
    i2c_control: u32 = 0, // 0x30
    phy_vendor_control: u32 = 0, // 0x34
    gpio: u32 = 0, // 0x38
    user_id: u32 = 0, // 0x3c
    vendor_id: VendorId, // 0x40
    hardware_config_1: u32 = 0, // 0x44
    hardware_config_2: HwConfig2, // 0x48
    hardware_config_3: HwConfig3, // 0x4c
    hardware_config_4: HwConfig4, // 0x50
    lpm_config: u32 = 0, // 0x54
    global_power_down: u32 = 0, // 0x58
    global_fifo_config: u32 = 0, // 0x5c
    adp_control: u32 = 0, // 0x60
    _pad_0x64_0x9c: [39]u32, // 0x64 .. 0x9c
    host_periodic_tx_fifo_size: u32 = 0, // 0x100
    device_periodic_tx_fifo: [191]u32, // 0x104 .. 0x3fc
    host_registers: HostRegisters, // 0x400..0x440
    _pad_0x444_0x4fc: [47]u32, // 0x444..0x4fc
    host_channel_registers: [dwc_max_channels]HostChannelRegisters, // 0x500 .. 0x6ff
    _pad_0x700_0xdfc: [448]u32, // 0x700 - 0xdfc
    power_clock_control: u32 = 0, // 0xe00
};

pub const UsbController = struct {
    pub const VTable = struct {
        dumpStatus: *const fn (usb_controller: u64) void,
    };

    allocator: Allocator,
    core_registers: *volatile CoreRegisters,
    host_registers: *volatile HostRegisters,
    intc: *const LocalInterruptController,
    translations: *const AddressTranslations,
    power_controller: *PowerController,
    clock: *const Clock,
    root_port: RootPort,
    channels: ChannelSet,
    vtable: VTable = .{
        .dumpStatus = dumpStatusInteropShim,
    },

    fn dumpStatusInteropShim(usb_controller: u64) void {
        var self: *UsbController = @ptrFromInt(usb_controller);
        self.dumpStatus();
    }

    pub fn init(
        allocator: Allocator,
        register_base: u64,
        intc: *LocalInterruptController,
        translations: *AddressTranslations,
        power: *PowerController,
        clock: *Clock,
    ) UsbController {
        return .{
            .allocator = allocator,
            .core_registers = @ptrFromInt(register_base),
            .host_registers = @ptrFromInt(register_base + 0x400),
            .intc = intc,
            .translations = translations,
            .power_controller = power,
            .clock = clock,
            .root_port = RootPort.init(),
            .channels = ChannelSet.init("DWC OTG Host controller channels", dwc_max_channels),
        };
    }

    pub fn hostControllerInitialize(self: *UsbController) !void {
        try self.powerOn();
        try self.verifyHostControllerDevice();
        try self.disableGlobalInterrupts();
        try self.connectInterruptHandler();
        try self.initializeControllerCore();
        try self.enableGlobalInterrupts();
        try self.initializeHost();
        try self.initializeRootPort();
    }

    fn powerOn(self: *UsbController) !void {
        var power_result = try self.power_controller.powerOn(.usb_hcd);

        if (power_result != .power_on) {
            std.log.err("Failed to power on USB device: {any}\n", .{power_result});
            return Error.PowerFailure;
        }
    }

    fn powerOff(self: *UsbController) !void {
        var power_result = try self.power_controller.powerOff(.usb_hcd);

        if (power_result != .power_off) {
            std.log.err("Failed to power off USB device: {any}\n", .{power_result});
            return Error.PowerFailure;
        }
    }

    fn verifyHostControllerDevice(self: *UsbController) !void {
        const id = self.core_registers.vendor_id;

        kprint("   DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

        if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
            std.log.warn(" gsnpsid = {x:0>8}\nvendor = {x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
            return Error.IncorrectDevice;
        }
    }

    fn disableGlobalInterrupts(self: *UsbController) !void {
        self.core_registers.ahb_config.global_interrupt_mask = 0;
    }

    fn enableGlobalInterrupts(self: *UsbController) !void {
        self.core_registers.ahb_config.global_interrupt_mask = 1;
    }

    fn connectInterruptHandler(self: *UsbController) !void {
        _ = self;
    }

    fn initializeControllerCore(self: *UsbController) !void {
        // clear bits 20 & 22 of core usb config register
        var config: UsbConfig = self.core_registers.usb_config;
        config.ulpi_ext_vbus_drv = 0;
        config.term_sel_dl_pulse = 0;
        self.core_registers.usb_config = config;

        try self.resetControllerCore();

        self.core_registers.usb_config.ulpi_utmi_sel = 1;
        self.core_registers.usb_config.phy_if = 1;

        const hw2 = self.core_registers.hardware_config_2;
        if (hw2.hs_phy_type == .ulpi and hw2.fs_phy_type == .dedicated) {
            self.core_registers.usb_config.ulpi_fsls = 1;
            self.core_registers.usb_config.ulpi_clk_sus_m = 1;
        } else {
            self.core_registers.usb_config.ulpi_fsls = 0;
            self.core_registers.usb_config.ulpi_clk_sus_m = 0;
        }

        var ahb = self.core_registers.ahb_config;
        ahb.dma_enable = 1;
        ahb.wait_axi_writes = 1;
        ahb.max_axi_burst = 0;
        self.core_registers.ahb_config = ahb;

        var negotiation = self.core_registers.usb_config;
        negotiation.hnp_capable = 0;
        negotiation.srp_capable = 0;
        self.core_registers.usb_config = negotiation;

        // enable common interrupts
        self.core_registers.interrupt_status = @bitCast(@as(u32, 0xffff_ffff));
    }

    fn resetControllerCore(self: *UsbController) !void {
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

    fn initializeHost(self: *UsbController) !void {
        self.core_registers.power_clock_control = 0;
        try self.flushTxFifo();
        self.delayMicros(1);
        try self.flushRxFifo();
        self.delayMicros(1);
        try self.powerHostPort();
        try self.enableHostInterrupts();
    }

    fn configPhyClockSpeed(self: *UsbController) !void {
        const core_config = self.core_registers.usb_config;
        const hw2 = self.core_registers.hardware_config_2;
        if (hw2.hs_phy_type == .ulpi and hw2.fs_phy_type == .dedicated and core_config.ulpi_fsls) {
            self.host_registers.config.fsls_pclk_sel = .sel_48_mhz;
        } else {
            self.host_registers.config.fsls_pclk_sel = .sel_30_60_mhz;
        }
    }

    fn flushTxFifo(self: *UsbController) !void {
        var reset = self.core_registers.reset;
        reset.tx_fifo_flush = 1;
        reset.tx_fifo_num = 0x10;
        self.core_registers.reset = reset;

        const reset_end = self.deadline(10);
        while (self.clock.ticks() < reset_end and self.core_registers.reset.tx_fifo_flush != 0) {}
    }

    fn flushRxFifo(self: *UsbController) !void {
        self.core_registers.reset.rx_fifo_flush = 1;
        const reset_end = self.deadline(10);
        while (self.clock.ticks() < reset_end and self.core_registers.reset.rx_fifo_flush != 0) {}
    }

    fn powerHostPort(self: *UsbController) !void {
        if (self.host_registers.port.power == 0) {
            self.host_registers.port.power = 1;
        }
    }

    fn enableHostInterrupts(self: *UsbController) !void {
        self.core_registers.interrupt_mask = @bitCast(@as(u32, 0));
        self.core_registers.interrupt_status = @bitCast(@as(u32, 0xffffffff));
        self.core_registers.interrupt_mask.host_channel_intr = 1;
    }

    fn initializeRootPort(self: *UsbController) !void {
        try self.enableRootPort();
        try self.root_port.configure();
    }

    fn enableRootPort(self: *UsbController) !void {
        // We should see the connect bit become true within 510 ms of
        // power on
        const connect_end = self.deadline(510);
        while (self.clock.ticks() <= connect_end and self.host_registers.port.connect == 0) {}

        self.delayMillis(100);

        var port = self.host_registers.port;
        port.connect_changed = 0;
        port.enabled = 0;
        port.enabled_changed = 0;
        port.overcurrent_changed = 0;
        port.reset = 1;
        self.host_registers.port = port;

        self.delayMillis(50);

        port = self.host_registers.port;
        port.connect_changed = 0;
        port.enabled = 0;
        port.enabled_changed = 0;
        port.overcurrent_changed = 0;
        port.reset = 0;
        self.host_registers.port = port;

        self.delayMillis(20);
    }

    pub fn getPortSpeed(self: *UsbController) !UsbSpeed {
        return switch (self.host_registers.port.speed) {
            .high => UsbSpeed.High,
            .full => UsbSpeed.Full,
            .low => UsbSpeed.Low,
            else => Error.ConfigurationError,
        };
    }

    // TODO migrate this to the clock
    fn deadline(self: *UsbController, millis: u32) u64 {
        const start_ticks = self.clock.ticks();
        const elapsed_ticks = millis * 1_000; // clock freq is 1Mhz
        return start_ticks + elapsed_ticks;
    }

    fn delayMillis(self: *UsbController, count: u32) void {
        self.delayMicros(count * 1000);
    }

    // TODO migrate this to the clock
    fn delayMicros(self: *UsbController, count: u32) void {
        const start_ticks = self.clock.ticks();
        const elapsed_ticks = count; // clock freq is 1Mhz
        const end_ticks = start_ticks + elapsed_ticks;
        while (self.clock.ticks() <= end_ticks) {}
    }

    pub fn dumpStatus(self: *UsbController) void {
        kprint("{s: >28}\n", .{"Core registers"});
        dumpRegister("otg_control", @bitCast(self.core_registers.otg_control));
        dumpRegister("ahb_config", @bitCast(self.core_registers.ahb_config));
        dumpRegister("usb_config", @bitCast(self.core_registers.usb_config));
        dumpRegister("reset", @bitCast(self.core_registers.reset));
        dumpRegister("interrupt_status", @bitCast(self.core_registers.interrupt_status));
        dumpRegister("interrupt_mask", @bitCast(self.core_registers.interrupt_mask));
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

    fn controlMessage(self: *UsbController, endpoint: *Endpoint, request_type: RequestType, request: u8, value: u16, index: u16, data: *anyopaque, data_size: u16) !u16 {
        var setup: usb.SetupPacket = .{
            .request_type = @bitCast(request_type),
            .request = request,
            .value = value,
            .index = index,
            .length = data_size,
        };
        var rq = Request.init(endpoint, data, data_size, &setup);

        try self.requestSubmitBlocking(&rq);

        return rq.result_length;
    }

    fn requestSubmitBlocking(self: *UsbController, request: *Request) !void {
        _ = self;

        request.status = 0;
    }
};

const Request = struct {
    status: u8,
    result_length: u32,
};

// ----------------------------------------------------------------------
// USB Device Model
// ----------------------------------------------------------------------

const Endpoint = struct {
    const EndpointDirection = enum {
        In,
        Out,
        InOut,
    };

    number: u8,
    type: EndpointType = .Control,
    direction: EndpointDirection = .Out,
    max_packet_size: u32 = DEFAULT_MAX_PACKET_SIZE,
    interval: u16, // milliseconds
};

const Device = struct {
    host: *UsbController = undefined,
    port: *RootPort = undefined,
    speed: UsbSpeed = undefined,
    address: Address = DEFAULT_ADDRESS,
    endpoint_0: Endpoint = undefined,
    hub_device: *Device = undefined,
    hub_address: u8 = 0,
    hub_port_number: u8 = 1,
    device_descriptor: DeviceDescriptor = undefined,
    config_descriptor: ConfigurationDescriptor = undefined,

    pub fn init() Device {
        return .{};
    }

    pub fn initialize(self: *Device, host: *UsbController, port: *RootPort, speed: UsbSpeed) !void {
        self.host = host;
        self.port = port;
        self.speed = speed;
    }
};

const RootPort = struct {
    host: *UsbController = undefined,
    device: *Device = undefined,

    pub fn init() RootPort {
        return .{
            .host = undefined,
            .device = undefined,
        };
    }

    pub fn initialize(self: *RootPort, host: *UsbController) !void {
        self.host = host;
        self.device = Device.init();
    }

    fn configure(self: *RootPort) !void {
        const speed = try self.host.getPortSpeed();

        self.device.initialize(self.host, self, speed) catch |err| {
            self.device = undefined;
            return err;
        };
    }
};
