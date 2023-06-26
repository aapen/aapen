/// Describe an address space, may be virtual or physical
const std = @import("std");
const assert = std.debug.assert;
const AddressSpace = @This();

pub const AddressType = enum { virtual, physical };

pub const Address = struct { type: AddressType, location: u64 };

regime: AddressType,
size: u64,
granule_size: u64,
page_mask: u64,

inline fn is_power_of_two(value: anytype) bool {
    return @popCount(value) == 1;
}

inline fn is_aligned(value: anytype, alignment: anytype) bool {
    assert(is_power_of_two(alignment));
    return (value & (alignment - 1)) == 0;
}

inline fn align_down(value: anytype, alignment: anytype) @TypeOf(value) {
    assert(is_power_of_two(alignment));
    return value & ~(alignment - 1);
}

inline fn align_up(value: anytype, alignment: anytype) @TypeOf(value) {
    assert(is_power_of_two(alignment));
    return (value + alignment - 1) & ~(alignment - 1);
}

pub fn create(regime: AddressType, size: u64, granule_size: usize) AddressSpace {
    assert(is_power_of_two(granule_size));

    return AddressSpace{
        .regime = regime,
        .size = size,
        .granule_size = granule_size,
        .page_mask = granule_size - 1,
    };
}

pub fn at(self: AddressSpace, location: usize) Address {
    return Address{ .type = self.regime, .location = location };
}

pub fn eql(self: AddressSpace, a: Address, b: Address) bool {
    _ = self;
    return a.location == b.location;
}

pub fn align_down_page(self: AddressSpace, a: Address) Address {
    return self.at(align_down(a.location, self.granule_size));
}

pub fn align_up_page(self: AddressSpace, a: Address) Address {
    return self.at(align_up(a.location, self.granule_size));
}

pub fn is_page_aligned(self: AddressSpace, a: Address) bool {
    return is_aligned(a.location, self.granule_size);
}

pub fn offset_in_page(self: AddressSpace, a: Address) usize {
    return a.location & self.page_mask;
}

test "virtual space returns virtual addresses" {
    const vspace = AddressSpace.create(.virtual, (1 << 64) - 1, 1 << 12);

    const vaddr1 = vspace.at(0x81fff);
    const vaddr2 = vspace.at(0x82000);
    const vaddr3 = vspace.at(0x81fff);

    const expect = @import("std").testing.expect;
    try expect(vspace.eql(vaddr1, vaddr1));
    try expect(!vspace.eql(vaddr1, vaddr2));
    try expect(vspace.eql(vaddr1, vaddr3));
}

test "rounding to page size" {
    const expect = @import("std").testing.expect;
    const pspace = AddressSpace.create(.physical, (1 << 48) - 1, 1 << 12);
    const paddr = pspace.at(pspace.granule_size + 100);
    try expect(pspace.eql(pspace.at(pspace.granule_size), pspace.align_down_page(paddr)));
    try expect(pspace.eql(pspace.at(2 * pspace.granule_size), pspace.align_up_page(paddr)));
}
