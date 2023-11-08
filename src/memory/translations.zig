const std = @import("std");
const ArrayList = std.ArrayList;

pub const AddressTranslations = ArrayList(AddressTranslation);

pub fn toChild(translations: *const AddressTranslations, parent_addr: u64) u64 {
    for (translations.items) |t| {
        if (t.parentBusContains(parent_addr)) {
            return t.parentToChild(parent_addr);
        }
    }
    return parent_addr;
}

pub fn toParent(translations: *const AddressTranslations, child_addr: u64) u64 {
    for (translations.items) |t| {
        if (t.childBusContains(child_addr)) {
            return t.childToParent(child_addr);
        }
    }
    return child_addr;
}

pub fn translation(child_address: u64, parent_address: u64, length: usize) AddressTranslation {
    return .{
        .parent_space_begin = parent_address,
        .parent_space_end = parent_address + length,
        .child_space_begin = child_address,
        .child_space_end = child_address + length,
        .length = length,
    };
}

pub const AddressTranslation = struct {
    parent_space_begin: u64,
    parent_space_end: u64,
    child_space_begin: u64,
    child_space_end: u64,
    length: usize,

    inline fn contains(actual: u64, begin: u64, end: u64) bool {
        return (actual >= begin and actual < end);
    }

    pub fn childBusContains(self: *const AddressTranslation, address: u64) bool {
        return contains(address, self.child_space_begin, self.child_space_end);
    }

    pub fn parentBusContains(self: *const AddressTranslation, address: u64) bool {
        return contains(address, self.parent_space_begin, self.parent_space_end);
    }

    inline fn translate(actual: u64, from_origin: u64, to_origin: u64) u64 {
        // this is written oddly to avoid u64 overflow
        const relative = actual - from_origin;
        return to_origin + relative;
    }

    pub fn parentToChild(self: *const AddressTranslation, address: u64) u64 {
        return translate(address, self.parent_space_begin, self.child_space_begin);
    }

    pub fn childToParent(self: *const AddressTranslation, address: u64) u64 {
        return translate(address, self.child_space_begin, self.parent_space_begin);
    }
};
