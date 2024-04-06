// From https://github.com/kubkon/zig-dwarfdump

const std = @import("std");
const Allocator = std.mem.Allocator;
const dwarf = std.dwarf;

const AbbrevTable = @import("AbbrevTable.zig");
const Attr = AbbrevTable.Attr;
const CompileUnit = @This();
const Elf = @import("Elf.zig");

const Parser = @import("Parser.zig");
const Loc = Parser.Loc;

const DebugSymbol = @import("DebugSymbol.zig");

children: std.ArrayListUnmanaged(usize) = .{},
dies: std.ArrayListUnmanaged(DebugInfoEntry) = .{},
header: Header,
loc: Loc,

pub fn deinit(cu: *CompileUnit, allocator: Allocator) void {
    for (cu.dies.items) |*die| {
        die.deinit(allocator);
    }
    cu.dies.deinit(allocator);
    cu.children.deinit(allocator);
}

pub fn addDie(cu: *CompileUnit, allocator: Allocator) !usize {
    const index = cu.dies.items.len;
    _ = try cu.dies.addOne(allocator);
    return index;
}

pub fn diePtr(cu: *const CompileUnit, index: usize) *DebugInfoEntry {
    return &cu.dies.items[index];
}

pub fn getDieAt(cu: *const CompileUnit, offset: usize) ?*DebugInfoEntry {
    for (cu.dies.items) |*die| {
        if (die.loc.pos == offset) return die;
    }
    return null;
}

pub fn nextCompileUnitOffset(cu: CompileUnit) u64 {
    return cu.loc.pos + switch (cu.header.dw_format) {
        .dwarf32 => @as(u64, 4),
        .dwarf64 => 12,
    } + cu.header.length;
}

pub fn format(
    cu: CompileUnit,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = cu;
    _ = unused_fmt_string;
    _ = options;
    _ = writer;
    @compileError("do not format CompileUnit directly; use fmtCompileUnit");
}

pub fn fmtCompileUnit(
    cu: *CompileUnit,
    table: AbbrevTable,
    elf: Elf,
) std.fmt.Formatter(formatCompileUnit) {
    return .{ .data = .{
        .cu = cu,
        .table = table,
        .elf = elf,
    } };
}

const FormatCompileUnitCtx = struct {
    cu: *CompileUnit,
    table: AbbrevTable,
    elf: Elf,
};

pub fn formatCompileUnit(
    ctx: FormatCompileUnitCtx,
    comptime unused_fmt_string: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = unused_fmt_string;
    _ = options;
    const cu = ctx.cu;
    try writer.print("{}: Compile Unit: {} (next unit at {})\n\n", .{
        cu.header.dw_format.fmtOffset(cu.loc.pos),
        cu.header,
        cu.header.dw_format.fmtOffset(cu.nextCompileUnitOffset()),
    });
    for (cu.children.items) |die_index| {
        const die = cu.diePtr(die_index);
        try writer.print("{}\n", .{die.fmtDie(ctx.table, cu, ctx.elf, null, 0)});
    }
}

pub const Header = struct {
    dw_format: Parser.Format,
    length: u64,
    version: u16,
    debug_abbrev_offset: u64,
    address_size: u8,

    pub fn format(
        header: Header,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_fmt_string;
        _ = options;
        try writer.print(
            "length = {}, " ++
                "format = {s}, " ++
                "version = 0x{x:0>4}, " ++
                "abbr_offset = {}, " ++
                "address_size = 0x{x:0>2}",
            .{
                header.dw_format.fmtOffset(header.length),
                @tagName(header.dw_format),
                header.version,
                header.dw_format.fmtOffset(header.debug_abbrev_offset),
                header.address_size,
            },
        );
    }
};

pub const DebugInfoEntry = struct {
    code: u64,
    loc: Loc,
    values: std.ArrayListUnmanaged([]const u8) = .{},
    children: std.ArrayListUnmanaged(usize) = .{},

    pub fn deinit(die: *DebugInfoEntry, allocator: Allocator) void {
        die.values.deinit(allocator);
        die.children.deinit(allocator);
    }

    pub fn format(
        die: DebugInfoEntry,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = die;
        _ = unused_fmt_string;
        _ = options;
        _ = writer;
        @compileError("do not format DebugInfoEntry directly; use fmtDie instead");
    }

    pub fn fmtDie(
        die: DebugInfoEntry,
        table: AbbrevTable,
        cu: *CompileUnit,
        elf: Elf,
        low_pc: ?u64,
        indent: usize,
    ) std.fmt.Formatter(formatDie) {
        return .{ .data = .{
            .die = die,
            .table = table,
            .cu = cu,
            .elf = elf,
            .low_pc = low_pc,
            .indent = indent,
        } };
    }

    const FormatDieCtx = struct {
        die: DebugInfoEntry,
        table: AbbrevTable,
        cu: *CompileUnit,
        elf: Elf,
        low_pc: ?u64 = null,
        indent: usize = 0,
    };

    fn formatDie(
        ctx: FormatDieCtx,
        comptime unused_fmt_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_fmt_string;
        _ = options;

        try writer.print("{}: ", .{ctx.cu.header.dw_format.fmtOffset(ctx.die.loc.pos)});
        const align_base: usize = 4 + switch (ctx.cu.header.dw_format) {
            .dwarf32 => @as(usize, 8),
            .dwarf64 => 16,
        };
        try fmtIndent(ctx.indent, writer);

        if (ctx.die.code == 0) {
            try writer.writeAll("NULL\n\n");
            return;
        }

        const decl = ctx.table.getDecl(ctx.die.code).?;
        try writer.print("{}\n", .{AbbrevTable.fmtTag(decl.tag)});

        var low_pc: ?u64 = ctx.low_pc;
        for (decl.attrs.items, ctx.die.values.items) |attr, value| {
            try fmtIndent(ctx.indent + align_base + 2, writer);
            try writer.print("{} (", .{AbbrevTable.fmtAt(attr.at)});

            formatAtFormInner(attr, value, ctx.cu, &low_pc, ctx.elf, writer) catch |err| switch (err) {
                error.UnhandledForm => try writer.print("error: unhandled FORM {x} for attribute", .{attr.form}),
                error.UnexpectedForm => try writer.print("error: unexpected FORM {x}", .{attr.form}),
                error.MalformedDwarf => try writer.print("error: malformed DWARF while parsing FORM {x}", .{attr.form}),
                error.Overflow, error.EndOfStream => unreachable,
                else => |e| return e,
            };

            try writer.writeAll(")\n");
        }
        try writer.writeByte('\n');

        for (ctx.die.children.items) |child_index| {
            const child = ctx.cu.diePtr(child_index);
            try writer.print("{}", .{child.fmtDie(ctx.table, ctx.cu, ctx.elf, low_pc, ctx.indent + 2)});
        }
    }

    fn formatAtFormInner(
        attr: Attr,
        value: []const u8,
        cu: *CompileUnit,
        low_pc: *?u64,
        elf: Elf,
        writer: anytype,
    ) !void {
        switch (attr.at) {
            dwarf.AT.stmt_list,
            dwarf.AT.ranges,
            => {
                const sec_offset = attr.getSecOffset(value, cu.header.dw_format) orelse
                    return error.MalformedDwarf;
                try writer.print("{x:0>16}", .{sec_offset});
            },

            dwarf.AT.low_pc => {
                const addr = attr.getAddr(value, cu.header) orelse
                    return error.MalformedDwarf;
                low_pc.* = addr;
                try writer.print("{x:0>16}", .{addr});
            },

            dwarf.AT.high_pc => {
                if (try attr.getConstant(value)) |offset| {
                    try writer.print("{x:0>16}", .{offset + low_pc.*.?});
                } else if (attr.getAddr(value, cu.header)) |addr| {
                    try writer.print("{x:0>16}", .{addr});
                } else return error.MalformedDwarf;
            },

            dwarf.AT.type,
            dwarf.AT.abstract_origin,
            => {
                const off = (try attr.getReference(value, cu.header.dw_format)) orelse
                    return error.MalformedDwarf;
                try writer.print("{x}", .{off});
            },

            dwarf.AT.comp_dir,
            dwarf.AT.producer,
            dwarf.AT.name,
            dwarf.AT.linkage_name,
            => {
                const str = attr.getString(value, cu.header.dw_format, elf) orelse
                    return error.MalformedDwarf;
                try writer.print("\"{s}\"", .{str});
            },

            dwarf.AT.language,
            dwarf.AT.calling_convention,
            dwarf.AT.encoding,
            dwarf.AT.decl_column,
            dwarf.AT.decl_file,
            dwarf.AT.decl_line,
            dwarf.AT.alignment,
            dwarf.AT.data_bit_offset,
            dwarf.AT.call_file,
            dwarf.AT.call_line,
            dwarf.AT.call_column,
            dwarf.AT.@"inline",
            => {
                const x = (try attr.getConstant(value)) orelse return error.MalformedDwarf;
                try writer.print("{x:0>16}", .{x});
            },

            dwarf.AT.location,
            dwarf.AT.frame_base,
            => {
                if (try attr.getExprloc(value)) |list| {
                    try writer.print("<0x{x}> {x}", .{ list.len, std.fmt.fmtSliceHexLower(list) });
                } else {
                    try writer.print("error: TODO check and parse loclist", .{});
                }
            },

            dwarf.AT.data_member_location => {
                if (try attr.getConstant(value)) |x| {
                    try writer.print("{x:0>16}", .{x});
                } else if (try attr.getExprloc(value)) |list| {
                    try writer.print("<0x{x}> {x}", .{ list.len, std.fmt.fmtSliceHexLower(list) });
                } else {
                    try writer.print("error: TODO check and parse loclist", .{});
                }
            },

            dwarf.AT.const_value => {
                if (try attr.getConstant(value)) |x| {
                    try writer.print("{x:0>16}", .{x});
                } else if (attr.getString(value, cu.header.dw_format, elf)) |str| {
                    try writer.print("\"{s}\"", .{str});
                } else {
                    try writer.print("error: TODO check and parse block", .{});
                }
            },

            dwarf.AT.count => {
                if (try attr.getConstant(value)) |x| {
                    try writer.print("{x:0>16}", .{x});
                } else if (try attr.getExprloc(value)) |list| {
                    try writer.print("<0x{x}> {x}", .{ list.len, std.fmt.fmtSliceHexLower(list) });
                } else if (try attr.getReference(value, cu.header.dw_format)) |off| {
                    try writer.print("{x:0>16}", .{off});
                } else return error.MalformedDwarf;
            },

            dwarf.AT.byte_size,
            dwarf.AT.bit_size,
            => {
                if (try attr.getConstant(value)) |x| {
                    try writer.print("{x}", .{x});
                } else if (try attr.getReference(value, cu.header.dw_format)) |off| {
                    try writer.print("{x}", .{off});
                } else if (try attr.getExprloc(value)) |list| {
                    try writer.print("<0x{x}> {x}", .{ list.len, std.fmt.fmtSliceHexLower(list) });
                } else return error.MalformedDwarf;
            },

            dwarf.AT.noreturn,
            dwarf.AT.external,
            dwarf.AT.variable_parameter,
            dwarf.AT.trampoline,
            => {
                const flag = attr.getFlag(value) orelse return error.MalformedDwarf;
                try writer.print("{}", .{flag});
            },

            else => {
                if (dwarf.AT.lo_user <= attr.at and attr.at <= dwarf.AT.hi_user) {
                    if (try attr.getConstant(value)) |x| {
                        try writer.print("{x}", .{x});
                    } else if (attr.getString(value, cu.header.dw_format, elf)) |string| {
                        try writer.print("\"{s}\"", .{string});
                    } else return error.UnhandledForm;
                } else return error.UnexpectedForm;
            },
        }
    }
};

fn fmtIndent(indent: usize, writer: anytype) !void {
    for (0..indent) |_| try writer.writeByte(' ');
}
