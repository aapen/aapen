/// Architecture-independent memory definition
///
/// Contains data structures and functions that will work
/// on any processor's MMU.

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

pub const KernelVirtualLayout = struct {
    max_virtual_address_inclusive: usize,
    descriptors: []const TranslationDescriptor,
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
};

pub const RangeInclusive = struct {
    start: usize,
    end: usize,
};

pub const MemoryAttributes = enum {
    CacheableDRAM,
    Device,
};

pub const AccessPermissions = enum {
    ReadOnly,
    ReadWrite,
};

test "sample layout" {
    const assert = @import("std").debug.assert;

    const layout = comptime [_]TranslationDescriptor{
        TranslationDescriptor.create(0x12340000, 0xfdff0000, 0x00000000, .ReadWrite, .CacheableDRAM, false, "Kernel code and read-only data"),
        TranslationDescriptor.create(0x1fff0000, 0x1fffffff, 0x201F0000, .ReadWrite, .Device, true, "Remapped copy of MMIO registers"),
        TranslationDescriptor.create(0x3f000000, 0x4000ffff, 0x00000000, .ReadWrite, .Device, true, "Identity-mapped location of MMIO registers"),
    };

    const kvl = KernelVirtualLayout{ .max_virtual_address_inclusive = 0xffffffffffff, .descriptors = &layout };

    assert(kvl.descriptors.len == 3);
}
