const usb = @import("../../usb.zig");

pub const ChannelCharacteristics = packed struct {
    max_packet_size: u11, // 0..10
    endpoint_number: u4, // 11..14
    endpoint_direction: enum(u1) {
        out = 0,
        in = 1,
    }, // 15
    _reserved_16: u1, // 16
    low_speed_device: u1, // 17
    endpoint_type: usb.EndpointType, // 18..19
    multi_count: u2, // 20..21
    device_address: u7, // 22..28
    odd_frame: u1, // 29
    disable: u1, // 30
    enable: u1, // 31
};

pub const ChannelSplitControl = packed struct {
    port_address: u7, // 0 .. 6
    hub_address: u7, // 7..13
    transaction_position: u2, // 14..15
    complete_split: u1, // 16
    _reserved_17_30: u14, // 17..30
    split_enable: u1, // 31
};

pub const ChannelInterrupt = packed struct {
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

    pub fn isStatusNakNyet(self: *ChannelInterrupt) bool {
        const st: u32 = @bitCast(self.*);
        const nak_mask: u32 = @bitCast(ChannelInterrupt{
            .nak_response_received = 1,
            .nyet_response_received = 1,
        });
        return (st & nak_mask) != 0;
    }

    pub fn isStatusError(self: *ChannelInterrupt) bool {
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

pub const DwcTransferSizePid = enum(u2) {
    // These are defined by the DWC2 chip itself
    Data0 = 0,
    Data1 = 2,
    Data2 = 1,
    Setup = 3,
};

pub const TransferSize = packed struct {
    transfer_size_bytes: u19, // 0..18
    transfer_size_packets: u10, // 19..28
    pid: DwcTransferSizePid, // 29..30
    do_ping: u1, // 31
};

pub const ChannelRegisters = extern struct {
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

pub const HostConfig = packed struct {
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

pub const HostFrameInterval = packed struct {
    interval: u16,
    _reserved: u16,
};

pub const HostFrames = packed struct {
    number: u16,
    remaining: u16,
};

pub const HostPeriodicFifo = packed struct {
    fifo_space_available: u16,
    request_queue_space_available: u8,
    request_queue_top: u8,
};

pub const HostPort = packed struct {
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

pub const HostRegisters = extern struct {
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
const VendorId = packed struct {
    device_minor_rev: u12 = 0,
    device_series: u4 = 0,
    device_vendor_id: u16 = 0, // (maybe this is the vendor id?)
};

pub const OtgControl = packed struct {
    _unknown: u9 = 0,
    hnp_enable: u1 = 0,
    _unknown_2: u22 = 0,
};

pub const AhbConfig = packed struct {
    global_interrupt_mask: u1, // 0
    max_axi_burst: u2, // 1..2
    _unknown_0: u1 = 0, // 3
    wait_axi_writes: u1, // 4
    dma_enable: u1, // 5
    _unknown_1: u17, // 6..22
    ahb_single: u1, // 23
    _unknown_2: u8, // 24 .. 31
};

pub const UsbConfig = packed struct {
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

pub const Reset = packed struct {
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

pub const InterruptStatus = packed struct {
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

pub const InterruptMask = InterruptStatus;

pub const RxStatus = packed struct {
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

pub const NonPeriodicTxFifoSize = packed struct {
    transmit_ram_start: u16,
    fifo_depth: u16,
};

pub const PeriodicTxFifoSize = NonPeriodicTxFifoSize;

pub const NonPeriodicTxFifoStatus = packed struct {
    tx_space_available: u16,
    rx_space_available: u8,
    tx_queue_top: u7,
    _reserved: u1,
};

pub const GeneralCoreConfig = packed struct {
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

pub const HwConfig2 = packed struct {
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

pub const HwConfig3 = packed struct {
    _unknown: u16, // 0..15
    dynamic_fifo_total_size: u16, // 16..31
};

pub const HwConfig4 = packed struct {
    _unknown_0: u25, // 0..24
    ded_fifo_enable: u1, // 25
    num_in_eps: u4, // 26..29
    _unknown_1: u2, // 30..31
};

pub const CoreRegisters = extern struct {
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
};
