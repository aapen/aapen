const std = @import("std");
const assert = std.debug.assert;

// purpose of this module
// - initialize the MMU
// - record physical regions: RAM, video, IO
// - map VAs to PAs
// - allocate pages on request
// - create heap allocator for kernel
//
// Depends on the BSP for
// - memory layout
// - RAM size
// - CPU page size

const KiB = 1024;
const MiB = 1024 * KiB;
const GiB = 1024 * MiB;

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

pub const AddressType = enum {
    virtual,
    physical,
};

const RawAddr = usize;

pub fn AddressSpace(comptime regime: AddressType) type {
    return struct {
        regime: AddressType,
        size: u64,
        granule_size: u64,

        PAGE_MASK: u64,

        const Self = @This();

        pub const Address = struct {
            location: u64,
            const InnerSelf = @This();
        };

        pub fn create(size: u64, granule_size: usize) Self {
            assert(is_power_of_two(granule_size));
            return .{
                .PAGE_MASK = granule_size - 1,
                .regime = regime,
                .size = size,
                .granule_size = granule_size,
            };
        }

        pub fn at(self: *const Self, location: usize) Address {
            _ = self;
            return .{ .location = location };
        }

        pub fn eql(self: *const Self, a: Address, b: Address) bool {
            _ = self;
            return a.location == b.location;
        }

        pub fn align_down_page(self: *const Self, a: Address) Address {
            return .{ .location = align_down(a.location, self.granule_size) };
        }

        pub fn align_up_page(self: *const Self, a: Address) Address {
            return .{ .location = align_up(a.location, self.granule_size) };
        }

        pub fn is_page_aligned(self: *const Self, a: Address) bool {
            return is_aligned(a.location, self.granule_size);
        }

        pub fn offset_in_page(self: *const Self, a: Address) usize {
            return a.location & self.PAGE_MASK;
        }
    };
}

test "virtual space returns virtual addresses" {
    const vspace = AddressSpace(.virtual).create((1 << 64) - 1, 1 << 12);

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
    const pspace = AddressSpace(.physical).create((1 << 48) - 1, 1 << 12);
    const paddr = pspace.at(pspace.granule_size + 100);
    try expect(pspace.eql(pspace.at(pspace.granule_size), pspace.align_down_page(paddr)));
    try expect(pspace.eql(pspace.at(2 * pspace.granule_size), pspace.align_up_page(paddr)));
}
