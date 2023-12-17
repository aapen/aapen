/// Protocol definition for USB 2.0 Hub devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
/// chapter 11 for all the details
///
/// This is not the class driver, it contains data structures and
/// constants defined by the protocol.
const descriptor = @import("descriptor.zig");
const DescriptorIndex = descriptor.DescriptorIndex;
const DescriptorType = descriptor.DescriptorType;
const Header = descriptor.Header;

const device = @import("device.zig");
const DeviceAddress = device.DeviceAddress;

const endpoint = @import("endpoint.zig");
const EndpointNumber = endpoint.EndpointNumber;
const EndpointType = endpoint.EndpointType;

const request = @import("request.zig");
const RequestTypeDirection = request.RequestTypeDirection;
const RequestTypeRecipient = request.RequestTypeRecipient;
const RequestTypeType = request.RequestTypeType;

const transaction = @import("transaction.zig");
const SetupPacket = transaction.SetupPacket;
const setup = transaction.setup;

/// See USB 2.0 specification, revision 2.0, section 11.23.2.1
pub const Characteristics = packed struct {
    power_switching_mode: enum(u2) {
        ganged = 0b00,
        individual = 0b01,
    },
    compound: enum(u1) {
        not_compound = 0b0,
        compound = 0b1,
    },
    overcurrent_protection_mode: enum(u2) {
        global = 0b00,
        individual = 0b01,
        none = 0b10,
        none2 = 0b11,
    },
    tt_think_time: enum(u2) {
        tt_8 = 0b00,
        tt_16 = 0b01,
        tt_24 = 0b10,
        tt_32 = 0b11,
    },
    port_indicators: enum(u1) {
        not_supported = 0b0,
        supported = 0b1,
    },
    _reserved_0: u8 = 0,
};

pub const ChangeStatusP = enum(u1) {
    not_changed = 0b0,
    changed = 0b1,
};

pub const OvercurrentStatusP = enum(u1) {
    not_detected = 0b0,
    detected = 0b1,
};

/// See USB 2.0 specification, revision 2.0, table 11-19
pub const HubStatusAndChangeStatus = packed struct {
    hub_status: packed struct {
        local_power_source: enum(u1) {
            local_power_good = 0b0,
            local_power_lost = 0b1,
        },
        overcurrent: OvercurrentStatusP,
        _reserved: u14 = 0,
    },
    change_status: packed struct {
        local_power_changed: ChangeStatusP,
        overcurrent_changed: ChangeStatusP,
        _reserved: u14 = 0,
    },
};

pub const PortStatus = packed struct {
    port_status: packed struct {
        connected: enum(u1) {
            not_connected = 0b0,
            connected = 0b1,
        },
        enabled: enum(u1) {
            disabled = 0b0,
            enabled = 0b1,
        },
        suspended: enum(u1) {
            not_suspended = 0b0,
            suspended = 0b1,
        },
        overcurrent: OvercurrentStatusP,
        reset: enum(u1) {
            not_asserted = 0b0,
            asserted = 0b1,
        },
        _reserved_0: u3 = 0,
        power: enum(u1) {
            off = 0b0,
            on = 0b1,
        },
        low_speed_device: enum(u1) {
            full_or_high = 0b0,
            low_speed = 0b1,
        },
        high_speed_device: enum(u1) {
            full_speed = 0b0,
            high_speed = 0b1,
        },
        test_mode: enum(u1) {
            disabled = 0b0,
            enabled = 0b1,
        },
        indicator_control: enum(u1) {
            default_colors = 0b0,
            controllable_colors = 0b1,
        },
        _reserved_1: u3,
    },
    port_change: packed struct {
        connected_changed: ChangeStatusP,
        enabled_changed: ChangeStatusP,
        suspended_changed: ChangeStatusP,
        overcurrent_changed: ChangeStatusP,
        reset_changed: ChangeStatusP,
        _reserved: u11 = 0,
    },
};

pub const HubDescriptor = packed struct {
    header: Header,
    number_ports: u8,
    characteristics: Characteristics,
    power_on_to_power_good: u8, // in 2 millisecond intervals
    controller_current: u8, // in milliamps
    // following controller_current is a variable # of bytes
    // containing a bitmap for "device removable". there is one bit
    // per number_ports, padded out to byte granularity

    // following the device removable bitmap is _another_ bitmap for
    // "port power control". it remains for compatibility but should
    // be set to all 1s.
};

/// See USB 2.0 specification, revision 2.0, section 11.24.2
pub const ClassRequestCode = enum(u8) {
    get_status = 0,
    clear_feature = 1,
    set_feature = 3,
    get_descriptor = 6,
    set_descriptor = 7,
    clear_tt_buffer = 8,
    reset_tt = 9,
    get_tt_state = 10,
    stop_tt = 11,
};

pub const FeatureSelector = union {
    hub_feature: enum(u16) {
        c_hub_local_power = 0,
        c_hub_over_current = 1,
    },
    port_feature: enum(u16) {
        port_connection = 0,
        port_enable = 1,
        port_suspend = 2,
        port_over_current = 3,
        port_reset = 4,
        port_power = 8,
        port_low_speed = 9,
        c_port_connection = 16,
        c_port_enable = 17,
        c_port_suspend = 18,
        c_port_over_current = 19,
        c_port_reset = 20,
        port_test = 21,
        port_indicator = 22,
    },
};

pub fn setupClearHubFeature(selector: FeatureSelector) SetupPacket {
    return setup(.device, .class, .host_to_device, .clear_feature, selector, 0, 0);
}

pub const TTDirection = enum(u1) {
    out = 0,
    in = 1,
};

const ClearTTBufferValue = packed struct {
    endpoint_number: EndpointNumber,
    device_address: DeviceAddress,
    endpoint_type: EndpointType,
    _reserved: u2 = 0,
    direction: TTDirection,
};

pub fn setupClearTTBuffer(device_address: DeviceAddress, endpoint_number: EndpointNumber, endpoint_type: EndpointType, direction: TTDirection, port_number: u8) SetupPacket {
    const val: ClearTTBufferValue = .{
        .endpoint_number = endpoint_number,
        .device_address = device_address,
        .endpoint_type = endpoint_type,
        .direction = direction,
    };

    return setup(.other, .class, .host_to_device, .clear_tt_buffer, val, port_number, 0);
}

pub fn setupGetHubDescriptor(descriptor_index: u8, descriptor_length: u16) SetupPacket {
    const val: u16 = @as(u16, @intFromEnum(DescriptorType.hub)) << 8 | @as(u8, descriptor_index);
    return setup(.device, .class, .device_to_host, .get_descriptor, val, 0, descriptor_length);
}

pub fn setupGetHubStatus() SetupPacket {
    return setup(.device, .class, .device_to_host, .get_status, 0, 0, 4);
}

pub fn setupGetPortStatus(port_number: u8) SetupPacket {
    return setup(.other, .class, .device_to_host, .get_status, 0, port_number, 4);
}

pub fn setupGetTTState(tt_flags: u16, tt_port: u16, tt_state_length: u16) SetupPacket {
    return setup(.other, .class, .device_to_host, .get_tt_state, tt_flags, tt_port, tt_state_length);
}

pub fn setupResetTT(tt_port: u16) SetupPacket {
    return setup(.other, .class, .host_to_device, .reset_tt, 0, tt_port, 0);
}

pub fn setupSetHubDescriptor(descriptor_type: DescriptorType, descriptor_index: DescriptorIndex, length: u16) SetupPacket {
    const val: u16 = @as(u16, descriptor_type) << 8 | descriptor_index;
    return setup(.device, .class, .host_to_device, .set_descriptor, val, 0, length);
}

pub fn setupStopTT(tt_port: u16) SetupPacket {
    return setup(.other, .class, .host_to_device, .stop_tt, 0, tt_port, 0);
}

pub fn setupSetHubFeature(selector: FeatureSelector) SetupPacket {
    return setup(.device, .class, .host_to_device, .set_feature, selector, 0, 0);
}

pub fn setupClearPortFeature(selector: FeatureSelector, port_number: u8, port_indicator: u8) SetupPacket {
    const index: u16 = @as(u16, port_indicator) << 8 | port_number;
    return setup(.other, .class, .host_to_device, .clear_feature, selector, index, 0);
}

pub fn setupSetPortFeature(feature: FeatureSelector, port_number: u8, port_indicator: u8) SetupPacket {
    const index: u16 = @as(u16, port_indicator) | port_number;
    return setup(.other, .class, .host_to_device, .set_feature, feature, index, 0);
}
