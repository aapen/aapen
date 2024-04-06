const std = @import("std");
const DebugSymbol = @This();

low_addr: u64 = 0,
high_addr: u64 = 0,
name: []const u8 = "",
linkage_name: []const u8 = "",
external: bool = false,

pub fn getName(symbol: *DebugSymbol) []const u8 {
    if (symbol.linkage_name.len > 0) {
        return symbol.linkage_name;
    } else if (symbol.name.len > 0) {
        return symbol.name;
    } else {
        return "";
    }
}

pub fn sort(symbols: std.ArrayListUnmanaged(DebugSymbol)) void {
    std.mem.sort(DebugSymbol, symbols.items, {}, compareByLowAddr);
}

fn compareByLowAddr(context: void, a: DebugSymbol, b: DebugSymbol) bool {
    return std.sort.asc(u64)(context, a.low_addr, b.low_addr);
}
