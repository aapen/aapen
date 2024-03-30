// The BSS symbols are provided by the linker script, which computes
// them from the object files produced by the compiler.
pub const Sections = struct {
    pub extern var __code_start: u8;
    pub extern var __code_end_exclusive: u8;
    pub extern var __data_start: u8;
    pub extern var __data_end_exclusive: u8;
    pub extern var __bss_start: u8;
    pub extern var __bss_end_exclusive: u8;
    pub extern var __page_tables_start: u8;
    pub extern var __debug_info_start: u8;
    pub extern var __debug_info_end: u8;
};

export fn bssInit() void {
    const bss_start: [*]u8 = @ptrCast(&Sections.__bss_start);
    const bss_end: [*]u8 = @ptrCast(&Sections.__bss_end_exclusive);
    const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);

    @memset(bss_start[0..bss_len], 0);
}
