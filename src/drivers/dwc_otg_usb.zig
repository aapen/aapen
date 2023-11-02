const std = @import("std");
const root = @import("root");
const kprint = root.kprint;

const hal = @import("../hal.zig");

const local_interrupt_controller = @import("arm_local_interrupt_controller.zig");
const bcm_power = @import("bcm_power.zig");

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const mailbox = @import("bcm_mailbox.zig");
const memory_map = @import("../hal/raspi3/memory_map.zig");

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

pub const Error = error{
    IncorrectDevice,
    PowerFailure,
};

const VendorId = packed struct {
    device_minor_rev: u12 = 0,
    device_series: u4 = 0,
    device_vendor_id: u16 = 0, // (maybe this is the vendor id?)
};

// ----------------------------------------------------------------------
// Channel Registers
// ----------------------------------------------------------------------

const ChannelCharacter = packed struct {
    max_packet_size: u11, // 0..10
    ep_number: u4, // 11..14
    ep_direction_in: u1, // 15
    _unknown_0: u1, // 16
    low_speed_device: u1, // 17
    ep_type: enum(u2) {
        control = 0,
        isochronous = 1,
        bulk = 2,
        interrupt = 3,
    }, // 18..19
    multi_cnt: u2, // 20..21
    device_address: u7, // 22..28
    per_odd_frame: u1, // 29
    disable: u1, // 30
    enable: u1, // 31
};

const ChannelSplitControl = packed struct {
    port_address: u7, // 0 .. 6
    hub_address: u7, // 7..13
    xact_pos: u2, // 14..15
    complete_split: u1, // 16
    _unknown_0: u14, // 17..30
    split_enable: u1, // 31
};

const ChannelInterrupt = packed struct {
    transfer_complete: u1, // 0
    halted: u1, // 1
    ahb_error: u1, // 2
    stall: u1, // 3
    nak: u1, // 4
    ack: u1, // 5
    nyet: u1, // 6
    xact_error: u1, // 7
    babble_error: u1, // 8
    frame_overrun: u1, // 9
    data_toggle_error: u1, // 10
    _unknown_0: u21, // 11..31
};

const ChannelTransferSize = packed struct {
    transfer_size_bytes: u19, // 0..18
    transfer_size_packets: u10, // 19..28
    pid: u2, // 29..30
    _unknown_0: u1, // 31
};

const HostChannelRegisters = extern struct {
    host_channel_character: ChannelCharacter, // 0x00
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
    }, // 0..1
    _unknown_0: u30,
};

const HostFrames = packed struct {
    number: u16,
    remaining: u16,
};

const HostPort = packed struct {
    connect: u1, // 0
    connect_changed: u1, // 1
    enable: u1, // 2
    enable_changed: u1, // 3
    overcurrent: u1, // 4
    overcurrent_changed: u1, // 5
    _unknown_0: u2, // 6..7
    reset: u1, // 8
    _unknown_1: u3, // 9..10
    power: u1, // 11
    _unknown_2: u5, // 12..17
    speed: enum(u2) {
        high = 0,
        full = 1,
        low = 2,
    }, // 18..19
    _unknown_3: u12, // 20..31
};

const HostRegisters = extern struct {
    host_config: HostConfig, // 0x00
    host_frame_interval: u32 = 0, // 0x04
    host_frame_num: HostFrames, // 0x08
    _unused_padding: u32 = 0, // 0x0c
    host_per_tx_fifo_status: u32 = 0, // 0x10
    host_all_channel_interrupt: u32 = 0, // 0x14
    host_all_channel_interrupt_mask: u32 = 0, // 0x18
    host_frame_last_base_addr: u32 = 0, // 0x1c
    _unused_padding_1: [8]u32, // 0x20 .. 0x3c
    host_port: HostPort, // 0x40

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
    _unknown_0: u3, // 0..2
    phy_if: u1, // 3
    ulpi_utmi_sel: u1, // 4
    _unknown_1: u3, // 5..7
    srp_capable: u1, // 8
    hnp_capable: u1, // 9
    _unknown_2: u7, // 10..16
    ulpi_fsls: u1, // 17
    _unknown_3: u1, // 18
    ulpi_clk_sus_m: u1, // 19
    ulpi_ext_vbus_drv: u1, // 20
    _unknown_4: u1, // 21
    term_sel_dl_pulse: u1, // 22
    _unknown_5: u9, // 23..31
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
    hc_intr: u1, // 25
    _unknown_2: u6, // 26..31
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
    hc_intr: u1, // 25
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
    op_mode: u3, // 0..2
    architecture: u2, // 3..4
    _unknown_0: u1, // 5
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
    _unknown_1: u4, // 10..13
    num_host_channels: u4, // 14..17
    _unknown_2: u14, // 18..31
};

const HwConfig3 = packed struct {
    _unknown: u16, // 0..15
    dfifo_depth: u16, // 16..31
};

const HwConfig4 = packed struct {
    _unknown_0: u25, // 0..24
    ded_fifo_enable: u1, // 25
    num_in_eps: u4, // 26..29
    _unknown_1: u2, // 30..31
};

const CoreRegisters = extern struct {
    core_otg_control: OtgControl, // 0x00
    core_otg_int: u32 = 0, // 0x04
    core_ahb_config: AhbConfig, // 0x08
    core_usb_config: UsbConfig, // 0x0c
    core_reset: Reset, // 0x10
    core_interrupt_status: InterruptStatus, // 0x14
    core_interrupt_mask: InterruptMask, // 0x18
    core_rx_status_rd: RxStatus, // 0x1c
    core_rs_status_pop: RxStatus, // 0x20
    core_rx_fifo_size: u32 = 0, // 0x24
    core_nper_tx_fifo_size: u32 = 0, // 0x28
    core_nper_tx_status: u32 = 0, // 0x2c
    core_i2c_control: u32 = 0, // 0x30
    core_phy_vendor_control: u32 = 0, // 0x34
    core_cpio: u32 = 0, // 0x38
    core_user_id: u32 = 0, // 0x3c
    core_vendor_id: VendorId, // 0x40
    core_hardware_config_1: u32 = 0, // 0x44
    core_hardware_config_2: HwConfig2, // 0x48
    core_hardware_config_3: HwConfig3, // 0x4c
    core_hardware_config_4: HwConfig4, // 0x50
    core_lpm_config: u32 = 0, // 0x54
    core_power_down: u32 = 0, // 0x58
    core_dfifo_config: u32 = 0, // 0x5c
    core_adp_control: u32 = 0, // 0x60
    _pad_0x64_0x7c: [7]u32, // 0x64 .. 0x7c
    vendor_mdio_control: u32 = 0, // 0x80
    vendor_mdio_data: u32 = 0, // 0x84
    vendor_vbus_drv: u32 = 0, // 0x88
    _pad_0x8c_0x9c: [5]u32, // 0x8c .. 0x9c
    core_host_per_tx_fifo_size: u32 = 0, // 0x100
    core_dev_per_tx_fifo: [15]u32, // 0x104 .. 0x140
    _pad_0x140_0x3fc: [176]u32, // 0x144 .. 0x3fc
    host_regs: HostRegisters, // 0x400
    _pad_0x444_0x4fc: [47]u32,
    hc_regs: HostChannelRegisters, // 0x500 .. 0x540
    _pad_0x700_0xe00: [448]u32,
    usb_power: u32 = 0, // 0xe00
};

pub const UsbController = struct {
    core_registers: *volatile CoreRegisters,
    host_registers: *volatile HostRegisters,
    intc: *const local_interrupt_controller.LocalInterruptController,
    translations: *const AddressTranslations,
    power_controller: *const bcm_power.BroadcomPowerController,

    pub fn hostControllerInitialize(self: *const UsbController) !void {
        try self.powerOn();
        try self.verifyHostControllerDevice();
    }

    fn powerOn(self: *const UsbController) !void {
        var power_result = try self.power_controller.powerOn(.usb_hcd);

        if (power_result != .power_on) {
            std.log.err("Failed to power on USB device: {any}\n", .{power_result});
            return Error.PowerFailure;
        }
    }

    fn powerOff(self: *const UsbController) !void {
        var power_result = try self.power_controller.powerOff(.usb_hcd);

        if (power_result != .power_off) {
            std.log.err("Failed to power off USB device: {any}\n", .{power_result});
            return Error.PowerFailure;
        }
    }

    fn verifyHostControllerDevice(self: *const UsbController) !void {
        const id = self.core_registers.core_vendor_id;

        kprint("   DWC2 OTG core rev: {x}.{x:0>3}\n", .{ id.device_series, id.device_minor_rev });

        if (id.device_vendor_id != 0x4f54 or (id.device_series != 2 and id.device_series != 3)) {
            std.log.warn(" gsnpsid = {x:0>8}\nvendor = {x:0>4}", .{ @as(u32, @bitCast(id)), id.device_vendor_id });
            return Error.IncorrectDevice;
        }
    }
};
