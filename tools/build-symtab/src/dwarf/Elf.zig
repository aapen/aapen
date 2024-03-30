const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const Error = error{
    InvalidHeader,
};

allocator: Allocator,
data: []const u8,
header: std.elf.Elf64_Ehdr,
debug_info_sect: ?std.elf.Elf64_Shdr = null,
debug_string_sect: ?std.elf.Elf64_Shdr = null,
debug_abbrev_sect: ?std.elf.Elf64_Shdr = null,
debug_frame: ?std.elf.Elf64_Shdr = null,
eh_frame: ?std.elf.Elf64_Shdr = null,

pub fn isElfFile(data: []const u8) bool {
    const header = @as(*const std.elf.Elf64_Ehdr, @ptrCast(@alignCast(data.ptr))).*;
    return std.mem.eql(u8, "\x7fELF", header.e_ident[0..4]);
}

fn init(allocator: Allocator, data: []const u8) !*Self {
    const self: *Self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,
        .data = data,
        .header = @as(*const std.elf.Elf64_Ehdr, @ptrCast(@alignCast(data.ptr))).*,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}

pub fn parse(allocator: Allocator, data: []const u8) !*Self {
    if (!isElfFile(data)) return Error.InvalidHeader;
    if (data.len < @sizeOf(std.elf.Elf64_Ehdr)) return Error.InvalidHeader;

    const self = try init(allocator, data);
    errdefer allocator.destroy(self);

    const shdrs = self.getShdrs();
    for (shdrs) |shdr| switch (shdr.sh_type) {
        std.elf.SHT_PROGBITS => {
            const sh_name = self.getShString(@as(u32, @intCast(shdr.sh_name)));
            if (std.mem.eql(u8, sh_name, ".debug_info")) {
                self.debug_info_sect = shdr;
            }
            if (std.mem.eql(u8, sh_name, ".debug_abbrev")) {
                self.debug_abbrev_sect = shdr;
            }
            if (std.mem.eql(u8, sh_name, ".debug_str")) {
                self.debug_string_sect = shdr;
            }
            if (std.mem.eql(u8, sh_name, ".debug_frame")) {
                self.debug_frame = shdr;
            }
            if (std.mem.eql(u8, sh_name, ".eh_frame")) {
                self.eh_frame = shdr;
            }
        },
        else => {},
    };

    return self;
}

pub fn getDebugInfoData(self: *const Self) ?[]const u8 {
    const shdr = self.debug_info_sect orelse return null;
    return self.getShdrData(shdr);
}

pub fn getDebugStringData(self: *const Self) ?[]const u8 {
    const shdr = self.debug_string_sect orelse return null;
    return self.getShdrData(shdr);
}

pub fn getDebugAbbrevData(self: *const Self) ?[]const u8 {
    const shdr = self.debug_abbrev_sect orelse return null;
    return self.getShdrData(shdr);
}

pub fn getDebugFrameData(self: *const Self) ?[]const u8 {
    const shdr = self.debug_frame orelse return null;
    return self.getShdrData(shdr);
}

pub fn getEhFrameData(self: *const Self) ?[]const u8 {
    const shdr = self.eh_frame orelse return null;
    return self.getShdrData(shdr);
}

pub fn getShdrByName(self: *const Self, name: []const u8) ?std.elf.Elf64_Shdr {
    const shdrs = self.getShdrs();
    for (shdrs) |shdr| {
        const shdr_name = self.getShString(shdr.sh_name);
        if (std.mem.eql(u8, shdr_name, name)) return shdr;
    }
    return null;
}

fn getShdrs(self: *const Self) []const std.elf.Elf64_Shdr {
    const shdrs = @as(
        [*]const std.elf.Elf64_Shdr,
        @ptrCast(@alignCast(self.data.ptr + self.header.e_shoff)),
    )[0..self.header.e_shnum];
    return shdrs;
}

fn getShdrData(self: *const Self, shdr: std.elf.Elf64_Shdr) []const u8 {
    return self.data[shdr.sh_offset..][0..shdr.sh_size];
}

fn getShString(self: *const Self, off: u32) []const u8 {
    const shdr = self.getShdrs()[self.header.e_shstrndx];
    const shstrtab = self.getShdrData(shdr);
    std.debug.assert(off < shstrtab.len);
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(shstrtab.ptr + off)), 0);
}

pub fn getArch(self: *const Self) ?std.Target.Cpu.Arch {
    return self.header.e_machine.toTargetCpuArch();
}

pub fn getDwarfString(self: *const Self, off: u64) []const u8 {
    const debug_str = self.getDebugStringData().?;
    std.debug.assert(off < debug_str.len);
    return std.mem.sliceTo(@as([*:0]const u8, @ptrCast(debug_str.ptr + off)), 0);
}
