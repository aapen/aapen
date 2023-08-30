const std = @import("std");
const ArrayList = std.ArrayList;

pub const AddressTranslations = ArrayList(*AddressTranslation);

pub const AddressTranslation = struct {
    child_address: u64,
    parent_address: u64,
    length: usize,

    // TODO add fns for child-to-parent and parent-to-child
};
