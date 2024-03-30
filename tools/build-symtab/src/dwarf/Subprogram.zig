const std = @import("std");
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

pub fn sort(subprograms: std.ArrayListUnmanaged(Subprogram)) void {
    std.mem.sort(Subprogram, subprograms.items, {}, compareByLowPc);
}

fn compareByLowPc(context: void, a: Subprogram, b: Subprogram) bool {
    return std.sort.asc(u64)(context, a.low_pc, b.low_pc);
}
