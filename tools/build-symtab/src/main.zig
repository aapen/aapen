const std = @import("std");
const Allocator = std.mem.Allocator;
const le = std.builtin.Endian.Little;

const Parser = @import("dwarf/Parser.zig");
const Subprogram = @import("dwarf/Subprogram.zig");

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

    const stdout = std.io.getStdOut().writer();

    var subprograms = try dump.accumulateSubprograms(allocator);
    defer subprograms.deinit(allocator);

    var addrtable = try DynamicString.init(allocator);
    defer addrtable.deinit();

    var strindex = try DynamicString.init(allocator);
    defer strindex.deinit();

    var strtable = try DynamicString.init(allocator);
    defer strtable.deinit();

    try stdout.print("found {d} subprograms\n", .{subprograms.items.len});

    var idx: u64 = 0;
    for (subprograms.items) |*sub| {
        try addrtable.append(std.mem.asBytes(&sub.low_pc));
        try addrtable.append(std.mem.asBytes(&sub.high_pc));
        try addrtable.append(std.mem.asBytes(&idx));

        const currlen = strtable.length();
        try strtable.append(sub.getName());
        const newlen = strtable.length();
        const namelen = newlen - currlen;

        try strindex.append(std.mem.asBytes(&currlen));
        try strindex.append(std.mem.asBytes(&namelen));

        idx += 1;
    }

    // try dump.printCompileUnits(stdout);

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

    //   strtab_offset: u32 - byte offset from zero where the string table appears
    const strtab_offset: u32 = @truncate(12 + addrtable.length());
    try image_out_writer.writeInt(u32, strtab_offset, le);

    // symbol_table:
    //   symbol_entries: u32 - count of entries in the symbol table
    const symbol_entries: u32 = @truncate(idx);
    try image_out_writer.writeInt(u32, symbol_entries, le);

    //   repeated 'symbol_entries' times:
    //     low_pc: u64 - first byte (within the loaded image) within the symbol
    //     high_pc: u64 - last byte (within the loaded image) within the symbol
    //     symbol_name: u64 - index into the string table with the symbol's name
    try image_out_writer.writeAll(addrtable.asBytes());

    // string_table:
    //   repeated 'string_entries' times:
    //     string_offset: u32 - byte offset from the start of the string table
    //     string_length: u32 - byte count of the string, does not include null
    try image_out_writer.writeAll(strindex.asBytes());

    // string_bulk:
    //   bytes
    try image_out_writer.writeAll(strtable.asBytes());
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

    pub fn append(self: *DynamicString, str: []const u8) !void {
        try self.buffer.appendSlice(std.mem.sliceAsBytes(str));
    }

    pub fn asBytes(self: *DynamicString) []u8 {
        return self.buffer.items;
    }

    pub fn length(self: *DynamicString) usize {
        return self.buffer.items.len;
    }
};
