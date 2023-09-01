const std = @import("std");
const ArrayList = std.ArrayList;

pub const AddressTranslations = ArrayList(*AddressTranslation);

pub const AddressTranslation = struct {
    parent_space_begin: u64,
    parent_space_end: u64,
    child_space_begin: u64,
    child_space_end: u64,
    length: usize,

    pub fn init(self: *AddressTranslation, parent_address: u64, child_address: u64, length: usize) void {
        self.parent_space_begin = parent_address;
        self.parent_space_end = parent_address + length;
        self.child_space_begin = child_address;
        self.child_space_end = child_address + length;
        self.length = length;
    }

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
        return translate(address, self.parent_address, self.child_address);
    }

    pub fn childToParent(self: *const AddressTranslation, address: u64) u64 {
        return translate(address, self.child_address, self.parent_address);
    }
};
