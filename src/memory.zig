const manager = @import("memory/manager.zig");
pub const dumpFreelist = manager.dumpFreelist;
pub const Error = manager.Error;
pub const free = manager.free;
pub const get = manager.get;

const layout = @import("memory/layout.zig");
pub const Sections = layout.Sections;

const regions = @import("memory/region.zig");
pub const Regions = regions.Regions;
pub const Region = regions.Region;

const translations = @import("memory/translations.zig");
pub const AddressTranslation = translations.AddressTranslation;
pub const AddressTranslations = translations.AddressTranslations;
pub const translation = translations.translation;
pub const toChild = translations.toChild;
pub const toParent = translations.toParent;

pub fn init(start_addr: u64, end_addr: u64) void {
    manager.init(start_addr, end_addr);
}
