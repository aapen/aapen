const Forth = @import("forty/forth.zig");

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

pub fn defineModule(forth: *Forth) !void {
    try forth.defineConstant("code-start", @intFromPtr(&Sections.__code_start));
    try forth.defineConstant("code-end", @intFromPtr(&Sections.__code_end_exclusive));
    try forth.defineConstant("data-start", @intFromPtr(&Sections.__data_start));
    try forth.defineConstant("data-end", @intFromPtr(&Sections.__data_end_exclusive));
    try forth.defineConstant("bss-start", @intFromPtr(&Sections.__bss_start));
    try forth.defineConstant("bss-end", @intFromPtr(&Sections.__bss_end_exclusive));
    try forth.defineConstant("page-tables-start", @intFromPtr(&Sections.__page_tables_start));
    try forth.defineConstant("debug-info-start", @intFromPtr(&Sections.__debug_info_start));
    try forth.defineConstant("debug-info-end", @intFromPtr(&Sections.__debug_info_end));
}
