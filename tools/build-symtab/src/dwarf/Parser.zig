// From https://github.com/kubkon/zig-dwarfdump

const std = @import("std");
const Allocator = std.mem.Allocator;
const abi = std.dwarf.abi;
const dwarf = std.dwarf;
const VirtualMachine = dwarf.call_frame.VirtualMachine;
const leb = std.leb;
const log = std.log;

const AbbrevLookupTable = std.AutoHashMap(u64, struct { pos: usize, len: usize });
const AbbrevTable = @import("AbbrevTable.zig");
const CompileUnit = @import("CompileUnit.zig");
const DebugSymbol = @import("DebugSymbol.zig");
const Elf = @import("Elf.zig");
const Exprloc = @import("Exprloc.zig");
const Location = Exprloc.Location;

const Parser = @This();

allocator: Allocator,
abbrev_tables: std.ArrayListUnmanaged(AbbrevTable) = .{},
compile_units: std.ArrayListUnmanaged(CompileUnit) = .{},
elf: *Elf,

pub fn deinit(self: *Parser) void {
    for (self.abbrev_tables.items) |*table| {
        table.deinit(self.allocator);
    }
    self.abbrev_tables.deinit(self.allocator);
    for (self.compile_units.items) |*cu| {
        cu.deinit(self.allocator);
    }
    self.compile_units.deinit(self.allocator);
    self.elf.deinit();
}

pub fn parse(allocator: Allocator, elf_data: []const u8) !Parser {
    var self = Parser{
        .allocator = allocator,
        .elf = try Elf.parse(allocator, elf_data),
    };

    try self.parseAbbrevTables();
    try self.parseCompileUnits();

    return self;
}

fn parseAbbrevTables(self: *Parser) !void {
    const elf = self.elf;
    const debug_abbrev = elf.getDebugAbbrevData() orelse return;
    var stream = std.io.fixedBufferStream(debug_abbrev);
    var creader = std.io.countingReader(stream.reader());
    const reader = creader.reader();

    while (true) {
        if (creader.bytes_read >= debug_abbrev.len) break;

        const table = try self.abbrev_tables.addOne(self.allocator);
        table.* = .{
            .loc = .{ .pos = creader.bytes_read, .len = 0 },
        };

        while (true) {
            const code = try leb.readULEB128(u64, reader);
            if (code == 0) break;

            const tag = try leb.readULEB128(u64, reader);
            const children = (try reader.readByte()) > 0;

            const decl = try table.decls.addOne(self.allocator);
            decl.* = .{
                .code = code,
                .tag = tag,
                .children = children,
                .loc = .{ .pos = creader.bytes_read, .len = 1 },
            };

            while (true) {
                const at = try leb.readULEB128(u64, reader);
                const form = try leb.readULEB128(u64, reader);
                if (at == 0 and form == 0) break;

                const attr = try decl.attrs.addOne(self.allocator);
                attr.* = .{
                    .at = at,
                    .form = form,
                    .loc = .{ .pos = creader.bytes_read, .len = 0 },
                };
                attr.loc.len = creader.bytes_read - attr.loc.pos;
            }

            decl.loc.len = creader.bytes_read - decl.loc.pos;
        }

        table.loc.len = creader.bytes_read - table.loc.pos;
    }
}

fn parseCompileUnits(self: *Parser) !void {
    const elf = self.elf;
    const debug_info = elf.getDebugInfoData() orelse return;
    var stream = std.io.fixedBufferStream(debug_info);
    var creader = std.io.countingReader(stream.reader());
    const reader = creader.reader();

    while (true) {
        if (creader.bytes_read == debug_info.len) break;

        const cu = try self.compile_units.addOne(self.allocator);
        cu.* = .{
            .header = undefined,
            .loc = .{ .pos = creader.bytes_read, .len = 0 },
        };

        var length: u64 = try reader.readInt(u32, .Little);
        const is_64bit = length == 0xffffffff;
        if (is_64bit) {
            length = try reader.readInt(u64, .Little);
        }
        cu.header.dw_format = if (is_64bit) .dwarf64 else .dwarf32;
        cu.header.length = length;
        cu.header.version = try reader.readInt(u16, .Little);
        cu.header.debug_abbrev_offset = try readOffset(cu.header.dw_format, reader);
        cu.header.address_size = try reader.readInt(u8, .Little);

        const table = self.getAbbrevTable(cu.header.debug_abbrev_offset).?;
        try self.parseDebugInfoEntry(cu, table, null, &creader);

        cu.loc.len = creader.bytes_read - cu.loc.pos;
    }
}

fn parseDebugInfoEntry(
    self: *Parser,
    cu: *CompileUnit,
    table: AbbrevTable,
    parent: ?usize,
    creader: anytype,
) anyerror!void {
    while (creader.bytes_read < cu.nextCompileUnitOffset()) {
        const die = try cu.addDie(self.allocator);
        cu.diePtr(die).* = .{
            .code = undefined,
            .loc = .{ .pos = creader.bytes_read, .len = 0 },
        };
        if (parent) |p| {
            try cu.diePtr(p).children.append(self.allocator, die);
        } else {
            try cu.children.append(self.allocator, die);
        }

        const code = try leb.readULEB128(u64, creader.reader());
        cu.diePtr(die).code = code;

        if (code == 0) {
            if (parent == null) continue;
            return; // Close scope
        }

        const decl = table.getDecl(code) orelse @panic("no suitable abbreviation decl found");
        const data = self.elf.getDebugInfoData().?;
        try cu.diePtr(die).values.ensureTotalCapacityPrecise(self.allocator, decl.attrs.items.len);

        for (decl.attrs.items) |attr| {
            const start = creader.bytes_read;
            try advanceByFormSize(cu, attr.form, creader);
            const end = creader.bytes_read;
            cu.diePtr(die).values.appendAssumeCapacity(data[start..end]);
        }

        if (decl.children) {
            // Open scope
            try self.parseDebugInfoEntry(cu, table, die, creader);
        }

        cu.diePtr(die).loc.len = creader.bytes_read - cu.diePtr(die).loc.pos;
    }
}

fn advanceByFormSize(cu: *CompileUnit, form: u64, creader: anytype) !void {
    const reader = creader.reader();
    switch (form) {
        dwarf.FORM.strp,
        dwarf.FORM.sec_offset,
        dwarf.FORM.ref_addr,
        => {
            _ = try readOffset(cu.header.dw_format, reader);
        },

        dwarf.FORM.addr => try reader.skipBytes(cu.header.address_size, .{}),

        dwarf.FORM.block1,
        dwarf.FORM.block2,
        dwarf.FORM.block4,
        dwarf.FORM.block,
        => {
            const len: u64 = switch (form) {
                dwarf.FORM.block1 => try reader.readInt(u8, .Little),
                dwarf.FORM.block2 => try reader.readInt(u16, .Little),
                dwarf.FORM.block4 => try reader.readInt(u32, .Little),
                dwarf.FORM.block => try leb.readULEB128(u64, reader),
                else => unreachable,
            };
            for (0..len) |_| {
                _ = try reader.readByte();
            }
        },

        dwarf.FORM.exprloc => {
            const len = try leb.readULEB128(u64, reader);
            for (0..len) |_| {
                _ = try reader.readByte();
            }
        },
        dwarf.FORM.flag_present => {},

        dwarf.FORM.data1,
        dwarf.FORM.ref1,
        dwarf.FORM.flag,
        => try reader.skipBytes(1, .{}),

        dwarf.FORM.data2,
        dwarf.FORM.ref2,
        => try reader.skipBytes(2, .{}),

        dwarf.FORM.data4,
        dwarf.FORM.ref4,
        => try reader.skipBytes(4, .{}),

        dwarf.FORM.data8,
        dwarf.FORM.ref8,
        dwarf.FORM.ref_sig8,
        => try reader.skipBytes(8, .{}),

        dwarf.FORM.udata,
        dwarf.FORM.ref_udata,
        => {
            _ = try leb.readULEB128(u64, reader);
        },

        dwarf.FORM.sdata => {
            _ = try leb.readILEB128(i64, reader);
        },

        dwarf.FORM.string => {
            while (true) {
                const byte = try reader.readByte();
                if (byte == 0x0) break;
            }
        },

        else => {
            log.err("unhandled DW_FORM_* value with identifier {x}", .{form});
            return error.UnhandledDwFormValue;
        },
    }
}

fn walkCompileUnit(
    parser: *Parser,
    allocator: Allocator,
    symbols: *std.ArrayListUnmanaged(DebugSymbol),
    elf: *const Elf,
    cu: *const CompileUnit,
    die: *CompileUnit.DebugInfoEntry,
    table: *const AbbrevTable,
) !void {
    if (die.code == 0) return;

    const decl = table.getDecl(die.code).?;

    switch (decl.tag) {
        dwarf.TAG.compile_unit => {
            for (die.children.items) |die_index| {
                const child = cu.diePtr(die_index);
                try parser.walkCompileUnit(allocator, symbols, elf, cu, child, table);
            }
        },
        dwarf.TAG.variable => {
            const variable: *DebugSymbol = try symbols.addOne(allocator);
            variable.* = .{};
            var size: u64 = 0;
            for (decl.attrs.items, die.values.items) |attr, value| {
                switch (attr.at) {
                    dwarf.AT.name => {
                        variable.name = attr.getString(value, cu.header.dw_format, parser.elf.*) orelse return error.MalformedDwarf;
                    },
                    dwarf.AT.linkage_name => {
                        variable.linkage_name = attr.getString(value, cu.header.dw_format, parser.elf.*) orelse return error.MalformedDwarf;
                    },
                    dwarf.AT.location => {
                        const exprloc = try attr.getExprloc(value) orelse return error.MalformedDwarf;
                        const loc = Exprloc.evaluate(exprloc, allocator);

                        switch (loc) {
                            Location.unknown => {
                                // not a supported location
                                // expression, skip this variable.
                                _ = symbols.pop();
                                return;
                            },
                            Location.absolute => |addr| {
                                variable.low_addr = addr;
                            },
                        }
                    },
                    else => {},
                }
            }

            variable.high_addr = variable.low_addr + size;

            if (variable.name.len == 0 and variable.linkage_name.len == 0) {
                // it has no name (but I have no idea why this happens)
                _ = symbols.pop();
            }

            if (variable.high_addr == 0 and variable.low_addr == 0) {
                // it was optimized out
                _ = symbols.pop();
            }
        },
        dwarf.TAG.label => {
            const label: *DebugSymbol = try symbols.addOne(allocator);
            label.* = .{};

            for (decl.attrs.items, die.values.items) |attr, value| {
                switch (attr.at) {
                    dwarf.AT.name => {
                        label.name = attr.getString(value, cu.header.dw_format, parser.elf.*) orelse return error.MalformedDwarf;
                    },
                    dwarf.AT.low_pc => {
                        const addr = attr.getAddr(value, cu.header) orelse return error.MalformedDwarf;
                        label.low_addr = addr;
                        label.high_addr = addr;
                    },
                    else => {},
                }
            }
        },
        dwarf.TAG.subprogram => {
            const subprogram: *DebugSymbol = try symbols.addOne(allocator);
            errdefer _ = symbols.pop();

            subprogram.* = .{};

            for (decl.attrs.items, die.values.items) |attr, value| {
                switch (attr.at) {
                    dwarf.AT.@"inline" => {
                        _ = symbols.pop();
                        return;
                    },
                    dwarf.AT.low_pc => {
                        const addr = attr.getAddr(value, cu.header) orelse return error.MalformedDwarf;
                        subprogram.low_addr = addr;
                    },
                    dwarf.AT.high_pc => {
                        if (try attr.getConstant(value)) |offset| {
                            subprogram.high_addr = @intCast(subprogram.low_addr + offset);
                        } else if (attr.getAddr(value, cu.header)) |addr| {
                            subprogram.high_addr = addr;
                        } else {
                            return error.MalformedDwarf;
                        }
                    },
                    dwarf.AT.name => {
                        subprogram.name = attr.getString(value, cu.header.dw_format, parser.elf.*) orelse return error.MalformedDwarf;
                    },
                    dwarf.AT.linkage_name => {
                        subprogram.linkage_name = attr.getString(value, cu.header.dw_format, parser.elf.*) orelse return error.MalformedDwarf;
                    },
                    dwarf.AT.abstract_origin => {
                        // This may not be a rule, but it's a
                        // pattern... whenever we see
                        // DW_AT_abstract_origin, it doesn't have a
                        // name. That means we can't use it to look up
                        // symbols by address.
                        _ = symbols.pop();
                        return;
                    },
                    dwarf.AT.external => {
                        subprogram.external = true;
                    },
                    else => {},
                }
            }

            // If the subprogram got here and still doesn't have a
            // name it may be a reference to a dynamically loaded
            // symbol. Since none of those will make it into our
            // binary image, we can discard them here.
            if (subprogram.name.len == 0 and subprogram.linkage_name.len == 0) {
                std.debug.print("subprogram had no name but made it through to here. removing it.\n", .{});
                _ = symbols.pop();
            }

            // if the low_pc is zero it's not useful for our debugging
            // (might be an external function, an inlined block, or a
            // non-exported variable name)
            if (subprogram.low_addr == 0) {
                _ = symbols.pop();
            }
        },
        else => {},
    }
}

pub fn accumulateDebugSymbols(parser: *Parser, allocator: Allocator) !std.ArrayListUnmanaged(DebugSymbol) {
    var subprograms = std.ArrayListUnmanaged(DebugSymbol){};

    for (parser.compile_units.items) |*cu| {
        const table = parser.getAbbrevTable(cu.header.debug_abbrev_offset).?;

        for (cu.children.items) |die_index| {
            const die = cu.diePtr(die_index);
            try parser.walkCompileUnit(allocator, &subprograms, parser.elf, cu, die, &table);
        }
    }

    return subprograms;
}

pub fn printAbbrevTables(self: Parser, writer: anytype) !void {
    try writer.writeAll(".debug_abbrev contents:\n");
    for (self.abbrev_tables.items) |table| {
        try writer.print("{}\n", .{table});
    }
}

pub fn printCompileUnits(self: Parser, writer: anytype) !void {
    try writer.writeAll(".debug_info contents:\n");
    for (self.compile_units.items) |*cu| {
        const table = self.getAbbrevTable(cu.header.debug_abbrev_offset).?;
        try writer.print("{}\n", .{cu.fmtCompileUnit(table, self.elf.*)});
    }
}

fn getAbbrevTable(self: Parser, off: u64) ?AbbrevTable {
    for (self.abbrev_tables.items) |table| {
        if (table.loc.pos == off) return table;
    }
    return null;
}

fn readOffset(format: Format, reader: anytype) !u64 {
    return switch (format) {
        .dwarf32 => try reader.readInt(u32, .Little),
        .dwarf64 => try reader.readInt(u64, .Little),
    };
}

const CieWithHeader = struct {
    cie: dwarf.CommonInformationEntry,
    header: dwarf.EntryHeader,

    vm: VirtualMachine = .{},

    // Instead of re-running the CIE instructions to print each FDE, the vm state
    // is restored to the post-CIE state instead.
    vm_snapshot_columns: usize = undefined,
    vm_snapshot_row: VirtualMachine.Row = undefined,

    pub fn deinit(self: *CieWithHeader, allocator: Allocator) void {
        self.vm.deinit(allocator);
    }
};

const WriteOptions = struct {
    llvm_compatibility: bool,
    frame_type: dwarf.DwarfSection,
    reg_ctx: abi.RegisterContext,
    addr_size: u8,
    endian: std.builtin.Endian,
};

const Section = struct {
    data: []const u8,
    offset: u64,
    frame_type: dwarf.DwarfSection,
};

pub fn printEhFrames(self: Parser, writer: anytype, llvm_compatibility: bool) !void {
    const elf = self.elf;
    const sections = [_]struct {
        name: []const u8,
        section: ?std.elf.Elf64_Shdr,
        data: ?[]const u8,
        frame_type: dwarf.DwarfSection,
    }{
        .{
            .name = ".debug_frame",
            .section = elf.debug_frame,
            .data = elf.getDebugFrameData(),
            .frame_type = .debug_frame,
        },
        .{
            .name = ".eh_frame",
            .section = elf.eh_frame,
            .data = elf.getEhFrameData(),
            .frame_type = .eh_frame,
        },
    };

    for (sections, 0..) |section, i| {
        if (i > 0) try writer.writeByte('\n');
        try writer.print("{s} contents:\n\n", .{section.name});
        if (section.section) |s| {
            if (s.sh_type != std.elf.SHT_NULL and s.sh_type != std.elf.SHT_NOBITS) {
                try self.printEhFrame(
                    writer,
                    llvm_compatibility,
                    .{
                        .data = section.data.?,
                        .offset = s.sh_addr,
                        .frame_type = section.frame_type,
                    },
                    false,
                );
            }
        }
    }
}

pub fn printEhFrame(self: Parser, writer: anytype, llvm_compatibility: bool, section: Section, is_macho: bool) !void {
    const write_options = WriteOptions{
        .llvm_compatibility = llvm_compatibility,
        .frame_type = section.frame_type,

        .reg_ctx = .{
            .eh_frame = section.frame_type == .eh_frame,
            .is_macho = is_macho,
        },

        // TODO: Use the addr size / endianness of the file, provide in section
        .addr_size = @sizeOf(usize),
        .endian = .Little,
    };

    var cies = std.AutoArrayHashMap(u64, CieWithHeader).init(self.allocator);
    defer {
        for (cies.keys()) |cie_offset| cies.getPtr(cie_offset).?.deinit(self.allocator);
        cies.deinit();
    }

    var stream: std.dwarf.FixedBufferReader = .{ .buf = section.data, .endian = write_options.endian };
    while (stream.pos < stream.buf.len) {
        const entry_header = try dwarf.EntryHeader.read(&stream, section.frame_type);
        switch (entry_header.type) {
            .cie => {
                const cie = try dwarf.CommonInformationEntry.parse(
                    entry_header.entry_bytes,
                    @as(i64, @intCast(section.offset)) - @as(i64, @intCast(@intFromPtr(section.data.ptr))),
                    false,
                    entry_header.format,
                    section.frame_type,
                    entry_header.length_offset,
                    write_options.addr_size,
                    write_options.endian,
                );

                const entry = try cies.getOrPut(entry_header.length_offset);
                std.debug.assert(!entry.found_existing);
                entry.value_ptr.* = .{ .cie = cie, .header = entry_header };

                try self.writeCie(writer, write_options, entry.value_ptr);
            },
            .fde => |cie_offset| {
                const cie_with_header = cies.getPtr(cie_offset) orelse return error.InvalidFDE;
                const fde = try dwarf.FrameDescriptionEntry.parse(
                    entry_header.entry_bytes,
                    @as(i64, @intCast(section.offset)) - @as(i64, @intCast(@intFromPtr(section.data.ptr))),
                    false,
                    cie_with_header.cie,
                    write_options.addr_size,
                    write_options.endian,
                );

                try self.writeFde(writer, write_options, cie_with_header, entry_header, fde);
            },
            .terminator => {
                try writer.print("{x:0>8} ZERO terminator\n", .{entry_header.length_offset});
                break;
            },
        }
    }
}

fn headerFormat(format: std.dwarf.Format) []const u8 {
    return if (format == .@"64") "{x:0>16}" else "{x:0>8}";
}

fn writeCie(
    self: Parser,
    writer: anytype,
    options: WriteOptions,
    cie_with_header: *CieWithHeader,
) !void {
    const expression_context = dwarf.expressions.ExpressionContext{
        .format = cie_with_header.header.format,
    };

    switch (cie_with_header.header.format) {
        inline else => |format| {
            const length_fmt = comptime headerFormat(format);
            try writer.print("{x:0>8} " ++ length_fmt ++ " " ++ length_fmt ++ " CIE\n", .{
                cie_with_header.cie.length_offset,
                cie_with_header.header.entryLength(),
                @as(u64, switch (options.frame_type) {
                    .eh_frame => dwarf.CommonInformationEntry.eh_id,
                    .debug_frame => if (format == .@"64") dwarf.CommonInformationEntry.dwarf64_id else dwarf.CommonInformationEntry.dwarf32_id,
                    else => unreachable,
                }),
            });
        },
    }

    const cie = &cie_with_header.cie;
    try writeFormat(writer, cie_with_header.header.format, true);
    try writer.print("  {s: <23}{}\n", .{ "Version:", cie.version });
    try writer.print("  {s: <23}\"{s}\"\n", .{ "Augmentation:", cie.aug_str });
    if (cie_with_header.cie.version == 4) {
        try writer.print("  {s: <23}{}\n", .{ "Address size:", cie.address_size });
        try writer.print("  {s: <23}{}\n", .{ "Segment desc size:", cie.segment_selector_size.? });
    }
    try writer.print("  {s: <23}{}\n", .{ "Code alignment factor:", cie.code_alignment_factor });
    try writer.print("  {s: <23}{}\n", .{ "Data alignment factor:", cie.data_alignment_factor });
    try writer.print("  {s: <23}{}\n", .{ "Return address column:", cie.return_address_register });

    // Oddly llvm-dwarfdump does not align this field with the rest
    if (cie.personality_routine_pointer) |p| try writer.print("  {s: <21}{x:0>16}\n", .{ "Personality Address:", p });

    if (cie.aug_data.len > 0) {
        try writer.print("  {s: <22}", .{"Augmentation data:"});
        for (cie.aug_data) |byte| {
            try writer.print(" {X:0>2}", .{byte});
        }
        try writer.writeByte('\n');
    }

    if (!options.llvm_compatibility) {
        try writer.writeAll("\n");
        if (cie.personality_enc) |p| try writer.print("  {s: <23}{X}\n", .{ "Personality Pointer Encoding:", p });
        try writer.print("  {s: <23}{X}\n", .{ "LSDA Pointer Encoding:", cie.lsda_pointer_enc });
        try writer.print("  {s: <23}{X}\n", .{ "FDE Pointer Encoding:", cie.fde_pointer_enc });
    }

    try writer.writeAll("\n");

    {
        var instruction_stream = std.io.fixedBufferStream(cie.initial_instructions);
        while (instruction_stream.pos < instruction_stream.buffer.len) {
            const instruction = try dwarf.call_frame.Instruction.read(&instruction_stream, options.addr_size, options.endian);
            const opcode = std.meta.activeTag(instruction);
            try writer.print("  DW_CFA_{s}:", .{@tagName(opcode)});
            try writeOperands(
                instruction,
                writer,
                cie.*,
                self.elf.getArch(),
                expression_context,
                options.reg_ctx,
                options.addr_size,
                options.endian,
            );
            _ = try cie_with_header.vm.step(self.allocator, cie.*, true, instruction);
            try writer.writeByte('\n');
        }
    }

    try writer.writeAll("\n");
    if (cie_with_header.vm.current_row.cfa.rule != .default) try writer.writeAll("  ");
    try self.writeRow(
        writer,
        cie_with_header.vm,
        cie_with_header.vm.current_row,
        expression_context,
        options.reg_ctx,
        options.addr_size,
        options.endian,
    );
    try writer.writeByte('\n');

    cie_with_header.vm_snapshot_columns = cie_with_header.vm.columns.items.len;
    cie_with_header.vm_snapshot_row = cie_with_header.vm.current_row;
}

fn writeFde(
    self: Parser,
    writer: anytype,
    options: WriteOptions,
    cie_with_header: *CieWithHeader,
    header: dwarf.EntryHeader,
    fde: dwarf.FrameDescriptionEntry,
) !void {
    const cie = &cie_with_header.cie;
    const expression_context = dwarf.expressions.ExpressionContext{
        .format = cie.format,
    };

    // TODO: Print <invalid offset> for cie if it didn't point to an actual CIE
    switch (cie_with_header.header.format) {
        inline else => |format| {
            const length_fmt = comptime headerFormat(format);
            try writer.print("{x:0>8} " ++ length_fmt ++ " " ++ length_fmt ++ " FDE cie={x:0>8} pc={x:0>8}...{x:0>8}\n", .{
                header.length_offset,
                header.entryLength(),
                switch (options.frame_type) {
                    .eh_frame => (header.length_offset + @as(u8, if (header.format == .@"64") 12 else 4)) - fde.cie_length_offset,
                    .debug_frame => fde.cie_length_offset,
                    else => unreachable,
                },
                fde.cie_length_offset,
                fde.pc_begin,
                fde.pc_begin + fde.pc_range,
            });
        },
    }

    try writeFormat(writer, cie_with_header.header.format, false);
    if (fde.lsda_pointer) |p| try writer.print("  LSDA Address: {x:0>16}\n", .{p});

    if (!options.llvm_compatibility) {
        if (fde.aug_data.len > 0) try writer.print("  {s: <23}{}\n", .{ "Augmentation data:", std.fmt.fmtSliceHexUpper(cie.aug_data) });
    }

    var instruction_stream = std.io.fixedBufferStream(fde.instructions);

    // First pass to print instructions and their operands
    while (instruction_stream.pos < instruction_stream.buffer.len) {
        const instruction = try dwarf.call_frame.Instruction.read(&instruction_stream, options.addr_size, options.endian);
        const opcode = std.meta.activeTag(instruction);
        try writer.print("  DW_CFA_{s}:", .{@tagName(opcode)});
        try writeOperands(
            instruction,
            writer,
            cie.*,
            self.elf.getArch(),
            expression_context,
            options.reg_ctx,
            options.addr_size,
            options.endian,
        );
        try writer.writeByte('\n');
    }

    try writer.writeByte('\n');

    // Second pass to run them and print the generated table
    instruction_stream.pos = 0;
    while (instruction_stream.pos < instruction_stream.buffer.len) {
        const instruction = try dwarf.call_frame.Instruction.read(&instruction_stream, options.addr_size, options.endian);
        const prev_row = try cie_with_header.vm.step(self.allocator, cie.*, false, instruction);
        if (cie_with_header.vm.current_row.offset != prev_row.offset) {
            try writer.print("  0x{x}: ", .{fde.pc_begin + prev_row.offset});
            try self.writeRow(
                writer,
                cie_with_header.vm,
                prev_row,
                expression_context,
                options.reg_ctx,
                options.addr_size,
                options.endian,
            );
        }
    }

    try writer.print("  0x{x}: ", .{fde.pc_begin + cie_with_header.vm.current_row.offset});
    try self.writeRow(
        writer,
        cie_with_header.vm,
        cie_with_header.vm.current_row,
        expression_context,
        options.reg_ctx,
        options.addr_size,
        options.endian,
    );

    // Restore the VM state to the result of the initial CIE instructions
    cie_with_header.vm.columns.items.len = cie_with_header.vm_snapshot_columns;
    cie_with_header.vm.current_row = cie_with_header.vm_snapshot_row;
    cie_with_header.vm.cie_row = null;

    try writer.writeByte('\n');
}

fn writeRow(
    self: Parser,
    writer: anytype,
    vm: VirtualMachine,
    row: VirtualMachine.Row,
    expression_context: dwarf.expressions.ExpressionContext,
    reg_ctx: abi.RegisterContext,
    addr_size: u8,
    endian: std.builtin.Endian,
) !void {
    const columns = vm.rowColumns(row);

    var wrote_anything = false;
    var wrote_separator = false;
    if (try writeColumnRule(
        row.cfa,
        writer,
        true,
        self.elf.getArch(),
        expression_context,
        reg_ctx,
        addr_size,
        endian,
    )) {
        wrote_anything = true;
    }

    // llvm-dwarfdump prints columns sorted by register number
    var num_printed: usize = 0;
    for (0..256) |register| {
        for (columns) |column| {
            if (column.register == @as(u8, @intCast(register))) {
                if (column.rule != .default and !wrote_separator) {
                    try writer.writeAll(": ");
                    wrote_separator = true;
                }

                if (try writeColumnRule(
                    column,
                    writer,
                    false,
                    self.elf.getArch(),
                    expression_context,
                    reg_ctx,
                    addr_size,
                    endian,
                )) {
                    if (num_printed != columns.len - 1) {
                        try writer.writeAll(", ");
                    }
                    wrote_anything = true;
                }

                num_printed += 1;
            }
        }

        if (num_printed == columns.len) break;
    }

    if (wrote_anything) try writer.writeByte('\n');
}

pub fn writeColumnRule(
    column: VirtualMachine.Column,
    writer: anytype,
    is_cfa: bool,
    arch: ?std.Target.Cpu.Arch,
    expression_context: dwarf.expressions.ExpressionContext,
    reg_ctx: abi.RegisterContext,
    addr_size_bytes: u8,
    endian: std.builtin.Endian,
) !bool {
    if (column.rule == .default) return false;

    if (is_cfa) {
        try writer.writeAll("CFA");
    } else {
        try writeRegisterName(writer, arch, column.register.?, reg_ctx);
    }

    try writer.writeByte('=');
    switch (column.rule) {
        .default => {},
        .undefined => try writer.writeAll("undefined"),
        .same_value => try writer.writeAll("S"),
        .offset, .val_offset => |offset| {
            if (offset == 0) {
                if (is_cfa) {
                    if (column.register) |cfa_register| {
                        try writer.print("{}", .{fmtRegister(cfa_register, reg_ctx, arch)});
                    } else {
                        try writer.writeAll("undefined");
                    }
                } else {
                    try writer.writeAll("[CFA]");
                }
            } else {
                if (is_cfa) {
                    if (column.register) |cfa_register| {
                        try writer.print("{}{d:<1}", .{ fmtRegister(cfa_register, reg_ctx, arch), offset });
                    } else {
                        try writer.print("undefined{d:<1}", .{offset});
                    }
                } else {
                    try writer.print("[CFA{d:<1}]", .{offset});
                }
            }
        },
        .register => |register| try writeRegisterName(writer, arch, register, reg_ctx),
        .expression => |expression| {
            if (!is_cfa) try writer.writeByte('[');
            try writeExpression(writer, expression, arch, expression_context, reg_ctx, addr_size_bytes, endian);
            if (!is_cfa) try writer.writeByte(']');
        },
        .val_expression => try writer.writeAll("TODO(val_expression)"),
        .architectural => try writer.writeAll("TODO(architectural)"),
    }

    return true;
}

fn writeExpression(
    writer: anytype,
    block: []const u8,
    arch: ?std.Target.Cpu.Arch,
    expression_context: dwarf.expressions.ExpressionContext,
    reg_ctx: abi.RegisterContext,
    addr_size_bytes: u8,
    endian: std.builtin.Endian,
) !void {
    var stream = std.io.fixedBufferStream(block);

    // Generate a lookup table from opcode value to name
    const opcode_lut_len = 256;
    const opcode_lut: [opcode_lut_len]?[]const u8 = comptime blk: {
        var lut: [opcode_lut_len]?[]const u8 = [_]?[]const u8{null} ** opcode_lut_len;
        for (@typeInfo(dwarf.OP).Struct.decls) |decl| {
            lut[@as(u8, @field(dwarf.OP, decl.name))] = decl.name;
        }

        break :blk lut;
    };

    switch (endian) {
        inline .Little, .big => |e| {
            switch (addr_size_bytes) {
                inline 2, 4, 8 => |size| {
                    const StackMachine = dwarf.expressions.StackMachine(.{
                        .addr_size = size,
                        .endian = e,
                        .call_frame_context = true,
                    });

                    const reader = stream.reader();
                    while (stream.pos < stream.buffer.len) {
                        if (stream.pos > 0) try writer.writeAll(", ");

                        const opcode = try reader.readByte();
                        if (opcode_lut[opcode]) |opcode_name| {
                            try writer.print("DW_OP_{s}", .{opcode_name});
                        } else {
                            // TODO: See how llvm-dwarfdump prints these?
                            if (opcode >= dwarf.OP.lo_user and opcode <= dwarf.OP.hi_user) {
                                try writer.print("<unknown vendor opcode: 0x{x}>", .{opcode});
                            } else {
                                try writer.print("<invalid opcode: 0x{x}>", .{opcode});
                            }
                        }

                        if (try StackMachine.readOperand(&stream, opcode, expression_context)) |value| {
                            switch (value) {
                                .generic => {}, // Constant values are implied by the opcode name
                                .register => |v| try writer.print(" {}", .{fmtRegister(v, reg_ctx, arch)}),
                                .base_register => |v| try writer.print(" {}{d:<1}", .{ fmtRegister(v.base_register, reg_ctx, arch), v.offset }),
                                else => try writer.print(" TODO({s})", .{@tagName(value)}),
                            }
                        }
                    }
                },
                else => return error.InvalidAddrSize,
            }
        },
    }
}

fn writeOperands(
    instruction: dwarf.call_frame.Instruction,
    writer: anytype,
    cie: dwarf.CommonInformationEntry,
    arch: ?std.Target.Cpu.Arch,
    expression_context: dwarf.expressions.ExpressionContext,
    reg_ctx: abi.RegisterContext,
    addr_size_bytes: u8,
    endian: std.builtin.Endian,
) !void {
    switch (instruction) {
        .set_loc => |i| try writer.print(" 0x{x}", .{i.address}),
        inline .advance_loc,
        .advance_loc1,
        .advance_loc2,
        .advance_loc4,
        => |i| try writer.print(" {}", .{i.delta * cie.code_alignment_factor}),
        inline .offset,
        .offset_extended,
        .offset_extended_sf,
        => |i| try writer.print(" {} {d}", .{
            fmtRegister(i.register, reg_ctx, arch),
            @as(i64, @intCast(i.offset)) * cie.data_alignment_factor,
        }),
        inline .restore,
        .restore_extended,
        .undefined,
        .same_value,
        => |i| try writer.print(" {}", .{fmtRegister(i.register, reg_ctx, arch)}),
        .nop => {},
        .register => |i| try writer.print(" {} {}", .{ fmtRegister(i.register, reg_ctx, arch), fmtRegister(i.target_register, reg_ctx, arch) }),
        .remember_state => {},
        .restore_state => {},
        .def_cfa => |i| try writer.print(" {} {d:<1}", .{ fmtRegister(i.register, reg_ctx, arch), @as(i64, @intCast(i.offset)) }),
        .def_cfa_sf => |i| try writer.print(" {} {d:<1}", .{ fmtRegister(i.register, reg_ctx, arch), i.offset * cie.data_alignment_factor }),
        .def_cfa_register => |i| try writer.print(" {}", .{fmtRegister(i.register, reg_ctx, arch)}),
        .def_cfa_offset => |i| try writer.print(" {d:<1}", .{@as(i64, @intCast(i.offset))}),
        .def_cfa_offset_sf => |i| try writer.print(" {d:<1}", .{i.offset * cie.data_alignment_factor}),
        .def_cfa_expression => |i| {
            try writer.writeByte(' ');
            try writeExpression(writer, i.block, arch, expression_context, reg_ctx, addr_size_bytes, endian);
        },
        .expression => |i| {
            try writer.print(" {} ", .{fmtRegister(i.register, reg_ctx, arch)});
            try writeExpression(writer, i.block, arch, expression_context, reg_ctx, addr_size_bytes, endian);
        },
        .val_offset => {},
        .val_offset_sf => {},
        .val_expression => {},
    }
}

fn writeFormat(writer: anytype, format: std.dwarf.Format, comptime is_cie: bool) !void {
    try writer.print("  {s: <" ++ (if (is_cie) "23" else "14") ++ "}{s}\n", .{ "Format:", if (format == .@"64") "DWARF64" else "DWARF32" });
}

fn writeUnknownReg(writer: anytype, reg_number: u8) !void {
    try writer.print("reg{}", .{reg_number});
}

pub fn writeRegisterName(
    writer: anytype,
    arch: ?std.Target.Cpu.Arch,
    reg_number: u8,
    reg_ctx: abi.RegisterContext,
) !void {
    if (arch) |a| {
        switch (a) {
            .x86 => {
                switch (reg_number) {
                    0 => try writer.writeAll("EAX"),
                    1 => try writer.writeAll("EDX"),
                    2 => try writer.writeAll("ECX"),
                    3 => try writer.writeAll("EBX"),
                    4 => if (reg_ctx.eh_frame and reg_ctx.is_macho) try writer.writeAll("EBP") else try writer.writeAll("ESP"),
                    5 => if (reg_ctx.eh_frame and reg_ctx.is_macho) try writer.writeAll("ESP") else try writer.writeAll("EBP"),
                    6 => try writer.writeAll("ESI"),
                    7 => try writer.writeAll("EDI"),
                    8 => try writer.writeAll("EIP"),
                    9 => try writer.writeAll("EFL"),
                    10 => try writer.writeAll("CS"),
                    11 => try writer.writeAll("SS"),
                    12 => try writer.writeAll("DS"),
                    13 => try writer.writeAll("ES"),
                    14 => try writer.writeAll("FS"),
                    15 => try writer.writeAll("GS"),
                    16...23 => try writer.print("ST{}", .{reg_number - 16}),
                    32...39 => try writer.print("XMM{}", .{reg_number - 32}),
                    else => try writeUnknownReg(writer, reg_number),
                }
            },
            .x86_64 => {
                switch (reg_number) {
                    0 => try writer.writeAll("RAX"),
                    1 => try writer.writeAll("RDX"),
                    2 => try writer.writeAll("RCX"),
                    3 => try writer.writeAll("RBX"),
                    4 => try writer.writeAll("RSI"),
                    5 => try writer.writeAll("RDI"),
                    6 => try writer.writeAll("RBP"),
                    7 => try writer.writeAll("RSP"),
                    8...15 => try writer.print("R{}", .{reg_number}),
                    16 => try writer.writeAll("RIP"),
                    17...32 => try writer.print("XMM{}", .{reg_number - 17}),
                    33...40 => try writer.print("ST{}", .{reg_number - 33}),
                    41...48 => try writer.print("MM{}", .{reg_number - 41}),
                    49 => try writer.writeAll("RFLAGS"),
                    50 => try writer.writeAll("ES"),
                    51 => try writer.writeAll("CS"),
                    52 => try writer.writeAll("SS"),
                    53 => try writer.writeAll("DS"),
                    54 => try writer.writeAll("FS"),
                    55 => try writer.writeAll("GS"),
                    // 56-57 Reserved
                    58 => try writer.writeAll("FS.BASE"),
                    59 => try writer.writeAll("GS.BASE"),
                    // 60-61 Reserved
                    62 => try writer.writeAll("TR"),
                    63 => try writer.writeAll("LDTR"),
                    64 => try writer.writeAll("MXCSR"),
                    65 => try writer.writeAll("FCW"),
                    66 => try writer.writeAll("FSW"),
                    67...82 => try writer.print("XMM{}", .{reg_number - 51}),
                    // 83-117 Reserved
                    118...125 => try writer.print("K{}", .{reg_number - 118}),
                    // 126-129 Reserved
                    else => try writeUnknownReg(writer, reg_number),
                }
            },
            .arm => {
                switch (reg_number) {
                    0...15 => try writer.print("R{}", .{reg_number}),
                    // 16-63 None
                    64...95 => try writer.print("S{}", .{reg_number - 64}),
                    96...103 => try writer.print("F{}", .{reg_number - 96}),

                    // Could also be ACC0-ACC7
                    104...111 => try writer.print("wCGR0{}", .{reg_number - 104}),
                    112...127 => try writer.print("wR0{}", .{reg_number - 112}),
                    128 => try writer.writeAll("SPSR"),
                    129 => try writer.writeAll("SPSR_FIQ"),
                    130 => try writer.writeAll("SPSR_IRQ"),
                    131 => try writer.writeAll("SPSR_ABT"),
                    132 => try writer.writeAll("SPSR_UND"),
                    133 => try writer.writeAll("SPSR_SVC"),
                    // 134-142 None
                    else => try writeUnknownReg(writer, reg_number),
                }
            },
            .aarch64 => {
                switch (reg_number) {
                    0...30 => try writer.print("W{}", .{reg_number}),
                    31 => try writer.writeAll("WSP"),
                    32 => try writer.writeAll("PC"),
                    33 => try writer.writeAll("ELR_mode"),
                    34 => try writer.writeAll("RA_SIGN_STATE"),
                    35 => try writer.writeAll("TPIDRRO_ELO"),
                    36 => try writer.writeAll("TPIDR_ELO"),
                    37 => try writer.writeAll("TPIDR_EL1"),
                    38 => try writer.writeAll("TPIDR_EL2"),
                    39 => try writer.writeAll("TPIDR_EL3"),
                    // 40-45 Reserved
                    46 => try writer.writeAll("VG"),
                    47 => try writer.writeAll("FFR"),
                    48...63 => try writer.print("P{}", .{reg_number - 48}),
                    64...95 => try writer.print("B{}", .{reg_number - 64}),
                    96...127 => try writer.print("Z{}", .{reg_number - 96}),
                    else => try writeUnknownReg(writer, reg_number),
                }
            },
            else => try writeUnknownReg(writer, reg_number),
        }
    } else try writeUnknownReg(writer, reg_number);
}

const FormatRegisterData = struct {
    reg_number: u8,
    reg_ctx: abi.RegisterContext,
    arch: ?std.Target.Cpu.Arch,
};

pub fn formatRegister(
    data: FormatRegisterData,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    try writeRegisterName(writer, data.arch, data.reg_number, data.reg_ctx);
}

pub fn fmtRegister(
    reg_number: u8,
    reg_ctx: abi.RegisterContext,
    arch: ?std.Target.Cpu.Arch,
) std.fmt.Formatter(formatRegister) {
    return .{
        .data = .{
            .reg_number = reg_number,
            .reg_ctx = reg_ctx,
            .arch = arch,
        },
    };
}

pub const Loc = struct {
    pos: usize,
    len: usize,
};

pub const Format = enum {
    dwarf32,
    dwarf64,

    pub fn fmtOffset(format: Format, offset: u64) std.fmt.Formatter(formatOffset) {
        return .{ .data = .{
            .format = format,
            .offset = offset,
        } };
    }

    const FmtOffsetCtx = struct {
        format: Format,
        offset: u64,
    };

    fn formatOffset(
        ctx: FmtOffsetCtx,
        comptime unused_format_string: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = unused_format_string;
        _ = options;
        switch (ctx.format) {
            .dwarf32 => try writer.print("0x{x:0>8}", .{ctx.offset}),
            .dwarf64 => try writer.print("0x{x:0>16}", .{ctx.offset}),
        }
    }
};
