/// Architecture-independent memory definition
///
/// Contains data structures and functions that will work
/// on any processor's MMU.
const arch_mmu = @import("arch/aarch64/memory.zig");

// ----------------------------------------------------------------------
// Control the MMU itself
// ----------------------------------------------------------------------
const MMUError = error{
    AlreadyEnabled,
};

pub fn enable_mmu_and_caching() !void {}

// ----------------------------------------------------------------------
// Describe memory layout
// ----------------------------------------------------------------------

const AllocationError = error{
    OutOfMemory,
};

pub const AddressProperties = struct {
    virtual_address: u64,
    physical_address: u64,
    access_permissions: AccessPermissions,
    memory_attributes: MemoryAttributes,
    execute_never: bool,
};

pub const KernelVirtualLayout = struct {
    max_virtual_address_inclusive: usize,
    descriptors: []const TranslationDescriptor,

    pub fn virtual_address_properties(self: KernelVirtualLayout, virtual_address: u64) ?AddressProperties {
        return for (self.descriptors) |d| {
            if (d.virtual_range.contains(virtual_address)) {
                break AddressProperties{
                    .virtual_address = virtual_address,
                    .physical_address = d.virtual_to_physical(virtual_address),
                    .access_permissions = d.access_permissions,
                    .memory_attributes = d.memory_attributes,
                    .execute_never = d.execute_never,
                };
            }
        } else {
            // Default to ordinary, identity-mapped RAM
            return AddressProperties{
                .virtual_address = virtual_address,
                .physical_address = virtual_address,
                .access_permissions = .ReadWrite,
                .memory_attributes = .CacheableDRAM,
                .execute_never = true,
            };
        };
    }
};

pub const TranslationDescriptor = struct {
    name: []const u8,
    virtual_range: RangeInclusive,

    physical_range_translation_offset: usize,
    memory_attributes: MemoryAttributes,
    access_permissions: AccessPermissions,
    execute_never: bool,

    pub fn create(virt_range_start: u64, virt_range_end: u64, phys_offset: u64, perm: AccessPermissions, attr: MemoryAttributes, execute_never: bool, name: []const u8) TranslationDescriptor {
        return .{
            .virtual_range = .{ .start = virt_range_start, .end = virt_range_end },
            .physical_range_translation_offset = phys_offset,
            .access_permissions = perm,
            .memory_attributes = attr,
            .execute_never = execute_never,
            .name = name,
        };
    }

    pub fn virtual_to_physical(self: TranslationDescriptor, virtual_address: u64) u64 {
        return (virtual_address + self.physical_range_translation_offset);
    }
};

pub const RangeInclusive = struct {
    start: u64,
    end: u64,

    pub fn contains(self: RangeInclusive, address: u64) bool {
        return self.start <= address and address < self.end;
    }
};

pub const MemoryAttributes = enum {
    CacheableDRAM,
    Device,
};

pub const AccessPermissions = enum {
    ReadOnly,
    ReadWrite,
};

// ----------------------------------------------------------------------
// Public functions
// ----------------------------------------------------------------------
test "sample layout" {
    const expect = @import("std").testing.expect;

    const layout = [_]TranslationDescriptor{
        TranslationDescriptor.create(0x12340000, 0x18000000, 0x00000000, .ReadOnly, .CacheableDRAM, false, "Kernel code and read-only data"),
        TranslationDescriptor.create(0x1fff0000, 0x1fffffff, 0x00200000, .ReadWrite, .Device, true, "Remapped copy of MMIO registers"),
        TranslationDescriptor.create(0x3f000000, 0x4000ffff, 0x00000000, .ReadWrite, .Device, true, "Identity-mapped location of MMIO registers"),
    };

    const kvl = KernelVirtualLayout{ .max_virtual_address_inclusive = 0xffffffffffff, .descriptors = &layout };

    try expect(kvl.descriptors.len == 3);

    try expect(kvl.virtual_address_properties(0x12340000).?.physical_address == 0x12340000);
    try expect(kvl.virtual_address_properties(0x17ffffff).?.physical_address == 0x17ffffff);
    try expect(kvl.virtual_address_properties(0x18000000).?.physical_address == 0x18000000);

    try expect(kvl.virtual_address_properties(0x17ffffff).?.access_permissions == .ReadOnly);
    try expect(kvl.virtual_address_properties(0x18000000).?.access_permissions == .ReadWrite);

    try expect(kvl.virtual_address_properties(0x1fff0000).?.physical_address == 0x201f0000);
    try expect(kvl.virtual_address_properties(0x1fff0000).?.memory_attributes == .Device);
    try expect(kvl.virtual_address_properties(0x1fff0000).?.access_permissions == .ReadWrite);
}
