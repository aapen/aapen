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
    endpoint_direction: enum(u1) {
        out = 0,
        in = 1,
    }, // 15
    _reserved_16: u1, // 16
    low_speed_device: u1, // 17
    endpoint_type: EndpointType, // 18..19
    multi_count: u2, // 20..21
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
    transfer_completed: u1 = 0, // 0
    halted: u1 = 0, // 1
    ahb_error: u1 = 0, // 2
    stall_response_received: u1 = 0, // 3
    nak_response_received: u1 = 0, // 4
    ack_response_received: u1 = 0, // 5
    nyet_response_received: u1 = 0, // 6
    transaction_error: u1 = 0, // 7
    babble_error: u1 = 0, // 8
    frame_overrun: u1 = 0, // 9
    data_toggle_error: u1 = 0, // 10
    buffer_not_available: u1 = 0, // 11
    excess_transaction_error: u1 = 0, // 12
    frame_list_rollover: u1 = 0, // 13
    _reserved_18_31: u18 = 0, // 14..31

    fn isStatusNakNyet(self: *ChannelInterrupt) bool {
        const st: u32 = @bitCast(self.*);
        const nak_mask: u32 = @bitCast(ChannelInterrupt{
            .nak_response_received = 1,
            .nyet_response_received = 1,
        });
        return (st & nak_mask) != 0;
    }

    fn isStatusError(self: *ChannelInterrupt) bool {
        const st: u32 = @bitCast(self.*);
        const error_mask: u32 = @bitCast(ChannelInterrupt{
            .ahb_error = 1,
            .stall_response_received = 1,
            .transaction_error = 1,
            .babble_error = 1,
            .frame_overrun = 1,
            .data_toggle_error = 1,
        });

        return (st & error_mask) != 0;
    }
};

const DwcTransferSizePid = enum(u2) {
    // These are defined by the DWC2 chip itself
    Data0 = 0,
    Data1 = 2,
    Data2 = 1,
    Setup = 3,
};

const TransferSize = packed struct {
    transfer_size_bytes: u19, // 0..18
    transfer_size_packets: u10, // 19..28
    pid: DwcTransferSizePid, // 29..30
    do_ping: u1, // 31
};

const ChannelRegisters = extern struct {
    channel_character: ChannelCharacteristics, // 0x00
    channel_split_control: ChannelSplitControl, // 0x04
    channel_int: ChannelInterrupt, // 0x08
    channel_int_mask: ChannelInterrupt, // 0x0c
    channel_transfer_size: TransferSize, // 0x10
    channel_dma_addr: u32 = 0, // 0x14
    _reserved: u32 = 0, // 0x18
    channel_dma_buf: u32 = 0, // 0x1c
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
    _reserved_0: u4, // 3..6
    enable_32khz: u1, // 7
    resume_valid: u8, // 8 .. 15
    _reserved_1: u7, // 16..22
    desc_dma: u1, // 23
    frame_list_entries: enum(u2) {
        list_entries_8 = 0,
        list_entries_16 = 1,
        list_entries_32 = 2,
        list_entries_64 = 3,
    }, // 24..25
    per_sched_enable: u1, //26
    _reserved_2: u4, // 27..30
    mode_ch_tim_en: u1, // 31
};

const HostFrameInterval = packed struct {
    interval: u16,
    _reserved: u16,
};

const HostFrames = packed struct {
    number: u16,
    remaining: u16,
};

const HostPeriodicFifo = packed struct {
    fifo_space_available: u16,
    request_queue_space_available: u8,
    request_queue_top: u8,
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
    frame_interval: HostFrameInterval, // 0x04
    frame_num: HostFrames, // 0x08
    _reserved_0x0c: u32 = 0, // 0x0c
    periodic_tx_fifo_status: HostPeriodicFifo, // 0x10
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
    soft_reset: u1, // 0 (rs)
    hclk_soft_reset: u1, // 1 (rs)
    frame_counter_reset: u1, // 2 (rs)
    _reserved_0: u1, // 3
    rx_fifo_flush: u1, // 4 (rs)
    tx_fifo_flush: u1, // 5 (rs)
    tx_fifo_flush_num: u5, // 6..10 (rw)
    _unknown_1: u19, // 11..29
    dma_request_in_progress: u1, // 30 (ro)
    ahb_idle: u1, // 31 (ro)
};

const InterruptStatus = packed struct {
    current_mode: u1, // 0
    mode_mismatch: u1, // 1
    otg_intr: u1, // 2
    sof_intr: u1, // 3
    rx_fifo_level: u1, // 4
    non_periodic_tx_fifo_empty: u1, // 5
    global_in_non_periodic_effective: u1, // 6
    global_out_nak_effective: u1, // 7
    _reserved_0: u2, // 8..9
    early_suspend: u1, // 10
    usb_suspend: u1, // 11
    usb_reset: u1, // 12
    enumeration_done: u1, // 13
    isochronous_out_packet_dropped: u1, // 14
    end_of_periodic_frame: u1, // 15
    _reserved_1: u2, // 16..17
    in_endpoint: u1, // 18
    out_endpoint: u1, // 19
    incomplete_isochronous_transfer: u1, // 20
    incomplete_periodic_transfer: u1, // 21
    data_fetch_suspended: u1, // 22
    _reserved_2: u1, // 23
    port_intr: u1, // 24
    host_channel_intr: u1, // 25
    periodic_tx_fifo_empty: u1, // 26
    _reserved_3: u1, // 27
    connector_id_status: u1, // 28
    disconnect: u1, // 29
    session_request: u1, // 30
    remote_wakeup: u1, // 31
};

const InterruptMask = InterruptStatus;

const RxStatus = packed struct {
    channel_number: u4, // 0..3
    byte_count: u11, // 4..14
    received_pid: enum(u2) {
        data0 = 0b00,
        data2 = 0b01,
        data1 = 0b10,
        mdata = 0b11,
    }, // 15..16
    packet_status: enum(u4) {
        in_packet_received = 0b0010,
        in_transfer_complete = 0b0011,
        data_toggle_error = 0b0101,
        channel_halted = 0b0111,
    }, // 17..20
    frame_number: u4, // 21..24
    _reserved_0: u7, // 25..31
};

const NonPeriodicTxFifoSize = packed struct {
    transmit_ram_start: u16,
    fifo_depth: u16,
};

const NonPeriodicTxFifoStatus = packed struct {
    tx_space_available: u16,
    rx_space_available: u8,
    tx_queue_top: u7,
    _reserved: u1,
};

const GeneralCoreConfig = packed struct {
    _reserved_0: u16, // 0..15
    power_down: enum(u1) {
        active = 0,
        deactivated = 1,
    }, // 16
    i2c_enable: enum(u1) {
        disabled = 0,
        enabled = 1,
    }, // 17
    vbus_sense_a: enum(u1) {
        disabled = 0,
        enabled = 1,
    }, // 18
    vbus_sense_b: enum(u1) {
        disabled = 0,
        enabled = 1,
    }, // 19
    sof_output_enable: enum(u1) {
        not_available = 0,
        available = 1,
    }, // 20
    vbus_sense_disable: enum(u1) {
        sense_available = 0,
        sense_unavailable = 1,
    }, // 21
    _reserved_1: u10, // 22..31
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

const PeriodicTxFifoSize = NonPeriodicTxFifoSize;

const CoreRegisters = extern struct {
    otg_control: OtgControl, // 0x00
    otg_interrupt: u32 = 0, // 0x04
    ahb_config: AhbConfig, // 0x08
    usb_config: UsbConfig, // 0x0c
    reset: Reset, // 0x10
    core_interrupt_status: InterruptStatus, // 0x14
    core_interrupt_mask: InterruptMask, // 0x18
    rx_status_read: RxStatus, // 0x1c
    rx_status_pop: RxStatus, // 0x20
    rx_fifo_size: u32 = 0, // 0x24
    nonperiodic_tx_fifo_size: NonPeriodicTxFifoSize, // 0x28
    nonperiodic_tx_status: NonPeriodicTxFifoStatus, // 0x2c
    i2c_control: u32 = 0, // 0x30
    phy_vendor_control: u32 = 0, // 0x34
    general_config: GeneralCoreConfig, // 0x38
    application_id: u32 = 0, // 0x3c
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
    host_periodic_tx_fifo_size: PeriodicTxFifoSize, // 0x100
    device_in_periodic_tx_fifo_size: [7]u32, // 0x104 .. 0x118

    // host_registers: HostRegisters, // 0x400..0x440
    // _pad_0x444_0x4fc: [47]u32, // 0x444..0x4fc
    // channel_registers: [dwc_max_channels]ChannelRegisters, // 0x500 .. 0x6ff
    // _pad_0x700_0xdfc: [448]u32, // 0x700 - 0xdfc
    // power_clock_control: u32 = 0, // 0xe00
};

pub const VTable = struct {
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
    .dumpStatus = dumpStatusInteropShim,
},

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
    try self.initializeRootPort();
}

fn powerOn(self: *Self) !void {
    var power_result = try self.power_controller.powerOn(.usb_hcd);

    if (power_result != .power_on) {
        std.log.err("Failed to power on USB device: {any}\n", .{power_result});
        return Error.PowerFailure;
    }
}

fn powerOff(self: *Self) !void {
    var power_result = try self.power_controller.powerOff(.usb_hcd);

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
    var buf: [32]u8 = [_]u8{0} ** 32;
    root.debug.kernelMessage(std.fmt.bufPrintZ(&buf, "{s} {d}", .{ "CHint", which_channel }) catch "");

    var stage = self.stage_data[which_channel];

    if (stage == undefined) {
        root.debug.kernelMessage("Spurious interrupt");
        return;
    }

    root.debug.kernelMessage(std.fmt.bufPrintZ(&buf, "{s} {x:0>8}", .{ "HCINTR", @as(u32, @bitCast(self.channel_registers[which_channel].channel_int)) }) catch "");

    var request = stage.request;

    switch (stage.substate) {
        .not_set => {
            root.debug.kernelMessage("Unexpected interrupt");
        },
        .wait_for_channel_disable => {
            self.channelStart(stage) catch {
                root.debug.kernelMessage("Error starting channel");
                // TODO clean up, this transaction will never finish
            };
            return;
        },
        .wait_for_transaction_complete => {
            // TODO clean and invalidate dcache for packet range
            var transfer_size = self.channel_registers[which_channel].channel_transfer_size;
            var channel_intr = self.channel_registers[which_channel].channel_int;

            // should check for done transaction here... remaining
            // transfer zero, and complete bit set
            //
            // ... without that, this infinitely restarts the
            // transaction
            //

            // restart halted transaction
            if (channel_intr.halted == 1) {
                // TODO should this enqueue the transaction for later?
                // self.transactionStart(stage) catch {
                //     root.debug.kernelMessage("Error starting txn");
                //     // TODO clean up, this transaction will never finish
                // };
                return;
            }

            stage.transactionComplete(
                channel_intr,
                transfer_size.transfer_size_packets,
                transfer_size.transfer_size_bytes,
            );
            return;
        },
    }

    switch (stage.state) {
        .not_set => {
            root.debug.kernelMessage("Unexpected state");
        },
        .no_split_transfer => {
            var status: ChannelInterrupt = stage.transaction_status;

            // TOOD handle nak / nyet status with periodic transaction
            if (status.isStatusError()) {
                std.log.err("usb txn failed (status 0x{x})", .{@as(u32, @bitCast(status))});
            } else {
                if (stage.status_stage) {
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
    try self.root_port.initialize(self);
}

pub fn getPortSpeed(self: *Self) !UsbSpeed {
    return switch (self.host_registers.port.speed) {
        .high => UsbSpeed.High,
        .full => UsbSpeed.Full,
        .low => UsbSpeed.Low,
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
    request_type: RequestType,
    request: u8,
    value: u16,
    index: u16,
    data: *align(DMA_ALIGNMENT) anyopaque,
    data_size: u16,
) !u19 {
    const raw_setup_data: []align(DMA_ALIGNMENT) u8 = try self.allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(SetupPacket));
    var setup: *align(DMA_ALIGNMENT) SetupPacket = @ptrCast(@alignCast(raw_setup_data));

    setup.* = .{
        .request_type = @bitCast(request_type),
        .request = request,
        .value = value,
        .index = index,
        .length = data_size,
    };
    var rq = try Request.init(self.allocator, endpoint, data, data_size, setup);

    try self.requestSubmitBlocking(rq);

    return rq.result_length;
}

fn channelAllocate(self: *Self) !ChannelId {
    var chan = try self.channels.allocate();
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
    channel: ChannelId,
    endpoint: *Endpoint,
    request: *Request,
    device: *Device,
    in: bool,
    status_stage: bool,
    speed: UsbSpeed,
    max_packet_size: u11,
    transfer_size: u16,
    bytes_per_transaction: u19,
    packets: u10,
    packets_per_transaction: u10,
    interrupt_mask: u32,
    temp_buffer: []u32,
    buffer_pointer: [*]u8,

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

    fn endpointType(self: *TransferStageData) EndpointType {
        return self.endpoint.type;
    }

    fn endpointNumber(self: *TransferStageData) u4 {
        return self.endpoint.number;
    }

    fn controllerPid(self: *TransferStageData) !DwcTransferSizePid {
        return switch (self.endpoint.pidNext(self.status_stage)) {
            PID.Setup => .Setup,
            PID.Data0 => .Data0,
            PID.Data1 => .Data1,
        };
    }

    fn resultLength(self: *TransferStageData) u19 {
        return @min(self.total_bytes_transferred, self.transfer_size);
    }

    fn transactionComplete(self: *TransferStageData, status: ChannelInterrupt, packets_left: u10, bytes_left: u19) void {
        self.transaction_status = status;

        // TODO check for NAK/NYET, see if the request should complete
        // when NAK/NYET. (Should only happen for Bulk endpoints)

        var packets_transferred: u10 = self.packets_per_transaction - packets_left;
        var bytes_transferred: u19 = self.bytes_per_transaction - bytes_left;

        self.total_bytes_transferred += bytes_transferred;
        self.buffer_pointer += bytes_transferred;

        // TODO this only happens if a) it's not a split transaction
        // or b) it _is_ a split and this is the last transaction in
        // the split
        self.endpoint.pidSkip(packets_transferred, self.status_stage);

        self.packets -= packets_transferred;

        if (self.transfer_size - self.total_bytes_transferred < self.bytes_per_transaction) {
            self.bytes_per_transaction = self.transfer_size - self.total_bytes_transferred;
        }
    }
};

fn createStageData(self: *Self, channel: ChannelId, request: *Request, in: bool, status_stage: bool) !*TransferStageData {
    const packet_size = request.endpoint.max_packet_size;

    const stage = try self.allocator.create(TransferStageData);
    stage.channel = channel;
    stage.request = request;
    stage.endpoint = request.endpoint;
    stage.device = request.endpoint.device;
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
        if (request.endpoint.pidNext(status_stage) == PID.Setup) {
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

fn transferStageAsync(self: *Self, request: *Request, in: bool, status_stage: bool) !void {
    const channel = try self.channelAllocate();

    const stage_data = try self.createStageData(channel, request, in, status_stage);
    self.stage_data[channel] = stage_data;

    self.channelInterruptEnable(channel);

    // TODO handle split transfers
    stage_data.state = .no_split_transfer;

    try self.transactionStart(stage_data);
}

fn transactionQueue(_: *Self, _: *TransferStageData) !void {}

fn transactionStart(self: *Self, stage_data: *TransferStageData) !void {
    const channel = stage_data.channel;
    var channel_characteristics = self.channel_registers[channel].channel_character;

    // if the channel is enabled, we must disable it (and wait for
    // that to complete
    if (channel_characteristics.enable == 1) {
        stage_data.substate = .wait_for_channel_disable;
        channel_characteristics.enable = 0;
        channel_characteristics.disable = 1;
        self.channel_registers[channel].channel_character = channel_characteristics;
        self.channel_registers[channel].channel_int_mask.halted = 1;

        // the rest happens when the interrupt fires
    } else {
        try self.channelStart(stage_data);
    }
}

fn channelStart(self: *Self, stage: *TransferStageData) !void {
    var channel = stage.channel;

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

    if (stage.speed == UsbSpeed.Low) {
        channel_characteristics.low_speed_device = 1;
    } else {
        channel_characteristics.low_speed_device = 0;
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

fn transferStage(self: *Self, request: *Request, in: bool, status_stage: bool) !void {
    const wait_until = self.deadline(request.timeout);

    const wait_block_assigned = try self.wait_block_allocations.allocate();
    defer {
        self.wait_blocks[wait_block_assigned] = false;
        self.wait_block_allocations.free(wait_block_assigned);
    }

    if (self.wait_blocks[wait_block_assigned]) {
        return Error.ConfigurationError;
    }

    self.wait_blocks[wait_block_assigned] = true;
    try self.transferStageAsync(request, in, status_stage);

    while (self.clock.ticks() < wait_until and self.wait_blocks[wait_block_assigned] == true) {
        // do nothing
    }

    if (self.wait_blocks[wait_block_assigned] == true) {
        // timeout elapsed... complain
        root.debug.kernelMessage("USB request timeout");
    }
}

fn requestSubmitBlocking(self: *Self, request: *Request) !void {
    request.status = 0;

    if (request.endpoint.type == EndpointType.Control) {
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
    descriptor_type: DescriptorType,
    which: DescriptorIndex,
    result: *align(64) Descriptor,
    buffer_size: u16,
    request_type: RequestType,
    index: u16,
) !void {
    const returned = try self.controlMessage(
        endpoint,
        request_type,
        @intFromEnum(StandardDeviceRequests.get_descriptor),
        @as(u16, @intFromEnum(descriptor_type)) << 8 | @as(u8, which),
        index,
        result,
        buffer_size,
    );

    if (returned != DEFAULT_MAX_PACKET_SIZE) {
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
    type: EndpointType = .Control,
    direction: EndpointDirection = .Out,
    max_packet_size: u11 = DEFAULT_MAX_PACKET_SIZE,
    interval: u16 = DEFAULT_INTERVAL, // milliseconds
    next_pid: PID = PID.Setup,

    fn pidNext(self: *Endpoint, status_stage: bool) PID {
        if (status_stage) {
            return PID.Data1;
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
            self.next_pid = PID.Setup;
        }
    }
};

const Device = struct {
    host: *Self,
    port: *RootPort,
    speed: UsbSpeed,
    address: Address,
    endpoint_0: Endpoint,
    function: [MAX_FUNCTIONS]Function,
    hub_device: *Device,
    hub_address: u8,
    hub_port_number: u8,
    device_descriptor: DeviceDescriptor,
    config_descriptor: ConfigurationDescriptor,
    descriptor_buffer: DescriptorPtr,

    pub fn init(allocator: Allocator) !*Device {
        var device = try allocator.create(Device);

        device.address = DEFAULT_ADDRESS;
        device.hub_address = 0;
        device.hub_port_number = 1;
        device.endpoint_0 = Endpoint{ .number = 0, .device = device };

        const raw_buffer = try allocator.alignedAlloc(u8, DMA_ALIGNMENT, @sizeOf(Descriptor));
        device.descriptor_buffer = @ptrCast(raw_buffer);

        return device;
    }

    pub fn initialize(self: *Device, host: *Self, port: *RootPort, speed: UsbSpeed) !void {
        self.host = host;
        self.port = port;
        self.speed = speed;

        root.debug.kernelMessage("Device.initialize:1");

        try host.descriptorQuery(&self.endpoint_0, .device, DEFAULT_DESCRIPTOR_INDEX, self.descriptor_buffer, DEFAULT_MAX_PACKET_SIZE, request_type_in, 0);

        root.debug.kernelMessage("Device.initialize:2");

        try self.descriptor_buffer.expectDeviceDescriptor();

        root.debug.kernelMessage("Device.initialize:3");
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
        const speed = try self.host.getPortSpeed();

        self.device = try Device.init(self.allocator);
        self.device.initialize(self.host, self, speed) catch |err| {
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
// Host, Device, Endpoint, Transfers
// ----------------------------------------------------------------------

// TODO all of it

pub const EndpointType = enum(u2) {
    Control = 0,
    Isochronous = 1,
    Bulk = 2,
    Interrupt = 3,
};

// ----------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------

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
        var request: *Request = try allocator.create(Request);

        request.* = .{
            .setup_data = setup_data,
            .endpoint = endpoint,
            .request_data = data,
            .request_data_size = request_data_size,
            .status = 0,
            .result_length = 0,
            .timeout = 0,
        };
        return request;
    }
};

// ----------------------------------------------------------------------
// Definitions from USB spec: Constants, Structures, and Packet Definitions
// ----------------------------------------------------------------------

pub const DEFAULT_MAX_PACKET_SIZE = 8;
pub const FIRST_DEDICATED_ADDRESS = 1;
pub const MAX_FUNCTIONS = 10;

pub const Address = u8;
pub const DEFAULT_ADDRESS: Address = 0;
pub const MAX_ADDRESS: Address = 63;

pub const DEFAULT_INTERVAL = 1;

/// Index of a descriptor
pub const DescriptorIndex = u8;
pub const DEFAULT_DESCRIPTOR_INDEX = 0;

/// Index of a string descriptor
pub const StringIndex = u8;

/// BCD coded number
pub const BCD = u16;

/// Assigned ID number
pub const ID = u16;

pub const PID = enum(u8) {
    Setup,
    Data0,
    Data1,
};

pub const UsbSpeed = enum {
    Low,
    Full,
    High,
    Super,
};

pub const SetupPacket = extern struct {
    request_type: RequestType,
    request: u8,
    value: u16,
    index: u16,
    length: u16,
};

pub const RequestType = packed struct {
    recipient: enum(u5) {
        device = 0b00000,
        interface = 0b00001,
        endpoint = 0b00010,
        other = 0b00011,
        // all other bit patterns are reserved
    }, // 0 .. 4
    type: enum(u2) {
        standard = 0b00,
        class = 0b01,
        vendor = 0b10,
        reserved = 0b11,
    }, // 5..6
    transfer_direction: enum(u1) {
        host_to_device = 0b0,
        device_to_host = 0b1,
    },
};

pub const request_type_in: RequestType = .{
    .recipient = .device,
    .type = .standard,
    .transfer_direction = .device_to_host,
};

pub const StandardDeviceRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    set_address = 0x05,
    get_descriptor = 0x06,
    set_descriptor = 0x07,
    get_configuration = 0x08,
    set_configuration = 0x09,
};

pub const StandardInterfaceRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    get_interface = 0x0a,
    set_interface = 0x11,
};

pub const StandardEndpointRequests = enum(u8) {
    get_status = 0x00,
    clear_feature = 0x01,
    set_feature = 0x03,
    synch_frame = 0x12,
};

pub const DescriptorType = enum(u8) {
    // not for use
    unknown = 0,

    // general
    device = 1,
    configuration = 2,
    string = 3,
    interface = 4,
    endpoint = 5,

    // class specific
    class_interface = 36,
    class_endpoint = 37,
};

pub const DeviceDescriptor = extern struct {
    length: u8 = 0,
    descriptor_type: DescriptorType = .unknown,
    usb_standard_compliance: BCD = 0,
    device_class: u8 = 0,
    device_subclass: u8 = 0,
    device_protocol: u8 = 0,
    max_packet_size: u8 = 0,
    vendor: ID = 0,
    product: ID = 0,
    device_release: BCD = 0,
    manufacturer_name: StringIndex = 0,
    product_name: StringIndex = 0,
    serial_number: StringIndex = 0,
    configuration_count: u8 = 0,
};

pub const ConfigurationDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,
    total_length: u16,
    interface_count: u8,
    configuration_value: u8,
    configuration: StringIndex,
    attributes: packed struct {
        _reserved_0: u5 = 0, // 0..5
        remote_wakeup: u1 = 0, // 5
        self_powered: u1 = 0, // 6
        _reserved_1: u1 = 1, // unused since USB 2.0
    },
    power_max: u8,
};

pub const InterfaceDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,
    interface_number: u8,
    alternate_setting: u8,
    endpoint_count: u8,
    interface_class: u8,
    interface_subclass: u8,
    interface_protocol: u8,
    interface_string: StringIndex,
};

pub const TransferType = enum(u2) {
    control = 0b00,
    isochronous = 0b01,
    bulk = 0b10,
    interrupt = 0b11,
};

pub const IsoSynchronizationType = enum(u2) {
    none = 0b00,
    asynchronous = 0b01,
    adaptive = 0b10,
    synchronous = 0b11,
};

pub const IsoUsageType = enum(u2) {
    data = 0b00,
    feedback = 0b01,
    explicit_feedback = 0b10,
    reserved = 0b11,
};

pub const EndpointDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,
    endpoint_address: u8,
    attributes: packed struct {
        transfer_type: TransferType, // 0..1
        iso_synch_type: IsoSynchronizationType, // 2..3
        usage_type: IsoUsageType, // 4..5
        _reserved_0: u2 = 0,
    },
    max_packet_size: u16,
    interval: u8, // polling interval in frames
};

pub const StringDescriptor = extern struct {
    length: u8,
    descriptor_type: DescriptorType,

    // For string descriptor 0, the remaining bytes (length - 2 / 2)
    // contain an array of u16's with the language codes of each
    // language this string is available in. The index of the
    // desired language in the array will be the `index` field in a request
    // to get string decriptor. That response will contain a unicode
    // encoded string of `length` bytes.
};

pub const Descriptor = extern union {
    header: packed struct {
        length: u8,
        descriptor_type: DescriptorType,
    },
    device: DeviceDescriptor,
    configuration: ConfigurationDescriptor,
    interface: InterfaceDescriptor,
    endpoint: EndpointDescriptor,
    string: StringDescriptor,

    const Error = error{
        LengthMismatch,
        UnexpectedType,
    };

    fn expectDeviceDescriptor(desc: *Descriptor) !void {
        if (desc.header.length != @sizeOf(DeviceDescriptor))
            return Descriptor.Error.LengthMismatch;

        if (desc.header.descriptor_type != DescriptorType.device)
            return Descriptor.Error.UnexpectedType;
    }
};

pub const DMA_ALIGNMENT = 64;
pub const DescriptorPtr = *align(DMA_ALIGNMENT) Descriptor;
