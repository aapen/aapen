const std = @import("std");
const memory_map = @import("memory_map.zig");
const UniformRegister = @import("../mmio_register.zig").UniformRegister;

// TODO Someday we'll get this from the device tree binary...
pub const xhci_start: u64 = memory_map.peripheral_base + 0x980000;

const XhciCapabilityRegisterBase = packed struct {
    length: u8 = 0,
    _reserved: u8 = 0,
    hci_version: u16 = 0, // Note: this field is binary coded decimal
};

pub const xhci_capability_register_base = UniformRegister(XhciCapabilityRegisterBase).init(xhci_start + 0x00);
