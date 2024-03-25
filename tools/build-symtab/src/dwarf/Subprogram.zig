const Subprogram = @This();

low_pc: u64 = 0,
high_pc: u64 = 0,
name: []const u8 = "",
linkage_name: []const u8 = "",
external: bool = false,

pub fn getName(subprogram: *Subprogram) []const u8 {
    if (subprogram.linkage_name.len > 0) {
        return subprogram.linkage_name;
    } else if (subprogram.name.len > 0) {
        return subprogram.name;
    } else {
        return "";
    }
}
