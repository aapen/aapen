const std = @import("std");
const Allocator = std.mem.Allocator;
const le = std.builtin.Endian.little;

const Parser = @import("dwarf/Parser.zig");
const DebugSymbol = @import("dwarf/DebugSymbol.zig");

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: build-symtab in.elf out.img\n", .{});
        std.process.exit(255);
    }

    // Open the input
    const elf_in: []u8 = args[1];
    const elf_in_path = try std.fs.realpathAlloc(allocator, elf_in);
    defer allocator.free(elf_in_path);
    const elf_in_f = try std.fs.openFileAbsolute(elf_in_path, .{ .mode = .read_only });
    defer elf_in_f.close();

    const elf_data = try elf_in_f.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(elf_data);

    var dump = try Parser.parse(allocator, elf_data);
    defer dump.deinit();

    var debug_symbols = try dump.accumulateDebugSymbols(allocator);
    defer debug_symbols.deinit(allocator);

    DebugSymbol.sort(debug_symbols);

    var addrtable = try DynamicString.init(allocator);
    defer addrtable.deinit();

    var strtable = try DynamicString.init(allocator);
    defer strtable.deinit();

    var strings = try DynamicString.init(allocator);
    defer strings.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("found {d} debug symbols\n", .{debug_symbols.items.len});
    // try dump.printCompileUnits(stdout);

    // for (debug_symbols.items, 0..) |*it, i| {
    //     try stdout.print("[{d}]: low = 0x{x:0>16}, high = 0x{x:0>16}, name = {s}, linkage_name = {s}\n", .{ i, it.low_addr, it.high_addr, it.name, it.linkage_name });
    // }

    var idx: u64 = 0;
    for (debug_symbols.items) |*sub| {
        const currlen: u64 = strings.length();

        try addrtable.append(std.mem.asBytes(&sub.low_addr));
        try addrtable.append(std.mem.asBytes(&sub.high_addr));
        try addrtable.append(std.mem.asBytes(&currlen));

        try strings.append(sub.getName());
        try strings.appendByte(0);

        idx += 1;
    }

    // Open the output file
    const image_out: []u8 = args[2];
    const image_out_f = try std.fs.cwd().openFile(image_out, .{ .mode = .read_write });
    defer image_out_f.close();

    // move to end of file
    try image_out_f.seekFromEnd(0);
    const image_out_writer = image_out_f.writer();

    // format of the symbol table file
    //
    //   magic: u32 - marker to detect proper format 0x00abacab
    const magic: u32 = 0x00abacab;
    try image_out_writer.writeInt(u32, magic, le);

    //   strings_offset: u32 - byte offset from zero where the strings appear
    //     note: strings_offset must be padded to 64-bit alignment
    const header_size = 16;
    const strings_offset: u32 = @truncate(header_size + addrtable.length());
    const alignment: u32 = 8;
    const aligned_strings_offset = (strings_offset + alignment - 1) & ~(alignment - 1);
    const strings_padding = aligned_strings_offset - strings_offset;
    try image_out_writer.writeInt(u32, aligned_strings_offset, le);

    //   symbol_entries: u32 - count of entries in the symbol table
    const symbol_entries: u32 = @truncate(idx);
    try image_out_writer.writeInt(u32, symbol_entries, le);

    // 4 bytes of padding to make the header square
    try image_out_writer.writeInt(u32, @as(u8, 0), le);

    //   repeated 'symbol_entries' times:
    //     low_pc: u64 - first byte (within the loaded image) within the symbol
    //     high_pc: u64 - last byte (within the loaded image) within the symbol
    //     symbol_name: u64 - index into the string table with the symbol's name
    try image_out_writer.writeAll(addrtable.asBytes());

    // align to 128-bit boundary so we can bitcast the memory as structs later
    for (0..strings_padding) |_| {
        try image_out_writer.writeByte(0);
    }

    // string_table:
    //   repeated 'string_entries' times:
    //     string_offset: u32 - byte offset from the start of the string table
    //     string_length: u32 - byte count of the string, does not include null
    try image_out_writer.writeAll(strtable.asBytes());

    // string_bulk:
    //   bytes
    try image_out_writer.writeAll(strings.asBytes());
}

pub const DynamicString = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) !DynamicString {
        return DynamicString{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *DynamicString) void {
        self.buffer.deinit();
    }

    pub fn appendByte(self: *DynamicString, b: u8) !void {
        try self.buffer.append(b);
    }

    pub fn append(self: *DynamicString, str: []const u8) !void {
        try self.buffer.appendSlice(std.mem.sliceAsBytes(str));
    }

    pub fn asBytes(self: *DynamicString) []u8 {
        return self.buffer.items;
    }

    pub fn length(self: *DynamicString) u32 {
        return @truncate(self.buffer.items.len);
    }
};
