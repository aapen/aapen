const translations = @import("memory/translations.zig");
pub const AddressTranslation = translations.AddressTranslation;
pub const AddressTranslations = translations.AddressTranslations;
pub const toChild = translations.toChild;
pub const toParent = translations.toParent;

const regions = @import("memory/region.zig");
pub const Region = regions.Region;

pub const AddressAndLength = struct { u64, u64 };
