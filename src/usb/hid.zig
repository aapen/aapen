/// Protocol definition for USB 2.0 Human Interface Devices
///
/// See USB 2.0 specification, revision 2.0 (dated April 27, 2000),
const descriptor = @import("descriptor.zig");
const BCD = descriptor.BCD;
const Header = descriptor.Header;

pub const HidDescriptor = extern struct {
    header: Header,
    hid_version: BCD,
    country_code: u8,
    descriptor_count: u8,
    descriptor_type: u8,
    length: u16,
};
