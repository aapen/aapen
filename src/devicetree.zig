const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;

const memory = @import("memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const AddressAndLength = memory.AddressAndLength;

const root = @import("root");
const kwarn = root.kwarn;

// This symbol is defined in boot.S.
// At boot time its value will be supplied by the firmware, which will
// point it at some memory.
pub extern var __fdt_address: usize;

// We use a fixed buffer allocator during boot (before we discover the
// RAM)
const parse_buffer_len = 256 * 1024;
var device_tree_parsed_buffer: [parse_buffer_len]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(device_tree_parsed_buffer[0..parse_buffer_len]);

pub var global_devicetree = Fdt{};
pub var root_node: *Fdt.Node = undefined;

pub fn init() void {
    global_devicetree.init(fba.allocator()) catch |err| {
        root.kerror(@src(), "Unable to initialize device tree. Things are likely to break: {any}\n", .{err});
    };

    root_node = global_devicetree.root_node;
}

pub inline fn cellsAs(cells: []const u32) u64 {
    var v: u64 = 0;
    for (cells) |c| {
        v <<= 32;
        v |= c;
    }
    return v;
}

pub const Fdt = struct {
    const Self = @This();

    const PHandle = u32;

    const NodeList = ArrayList(*Node);
    const AliasMap = StringHashMap([]const u8);
    const PHandleMap = AutoHashMap(PHandle, *Node);
    const PropertyList = ArrayList(*Property);

    // These constants come from the device tree specification.
    // See https://github.com/devicetree-org/devicetree-specification
    const compatible_version = 16;
    const magic_value = 0xd00dfeed;
    pub const tag_size: usize = @sizeOf(u32);

    // Member variables will be in native byte order
    struct_base: usize = undefined,
    struct_size: usize = undefined,
    strings_base: usize = undefined,
    strings_size: usize = undefined,

    aliases: AliasMap = undefined,
    phandles: PHandleMap = undefined,
    root_node: *Node = undefined,

    pub const Error = error{
        OutOfMemory,
        BadVersion,
        BadTagAlignment,
        BadPath,
        NotFound,
        NoAlias,
        AliasNotFound,
        IncorrectTag,
        NoTagAtOffset,
        BadContents,
        ValueUnavailable,
        ValueWrongLength,
    };

    /// Note: when reading from the fdt blob, these will all be
    /// big-endian
    ///
    /// Struct definition comes from the device tree specification
    const Header = extern struct {
        magic: u32,
        total_size: u32,
        off_dt_struct: u32,
        off_dt_strings: u32,
        off_mem_rsvmap: u32,
        version: u32,
        last_compatible_version: u32,
        boot_cpuid_physical: u32,
        size_dt_strings: u32,
        size_dt_struct: u32,
    };

    pub fn init(self: *Fdt, allocator: Allocator) !void {
        try self.initFromPointer(allocator, __fdt_address);
    }

    pub fn initFromPointer(self: *Fdt, allocator: Allocator, fdt_address: u64) !void {
        var h: *Header = @ptrFromInt(fdt_address);

        if (nativeByteOrder(h.magic) != magic_value) {
            return Error.NotFound;
        }

        if (nativeByteOrder(h.last_compatible_version) < compatible_version) {
            return Error.BadVersion;
        }

        // if those passed, we have a good blob.
        // from here, self.struct_base and self.strings_base will be
        // pre-added and in native byte order
        self.struct_base = fdt_address + nativeByteOrder(h.off_dt_struct);
        self.struct_size = nativeByteOrder(h.size_dt_struct);
        self.strings_base = fdt_address + nativeByteOrder(h.off_dt_strings);
        self.strings_size = nativeByteOrder(h.size_dt_strings);

        self.phandles = PHandleMap.init(allocator);
        self.root_node = try parse(self, allocator);

        try readAliases(self, allocator);
    }

    pub fn deinit(self: *Fdt) void {
        self.root_node.deinit();
        self.phandles.deinit();
        self.aliases.deinit();
    }

    pub fn nodeLookupByPath(self: *Fdt, path: []const u8) !*Node {
        if (path[0] == '/') {
            return self.root_node.lookupChildByPath(path, 1, path.len);
        } else {
            var end = path.len;

            // a path that doesn't start from root must be an
            // alias
            var q = charIndex('/', path, 0) orelse end;

            if (try self.nodeLookupByAlias(path[0..q])) |start_node| {
                if (q == end) {
                    return start_node;
                } else {
                    return start_node.lookupChildByPath(path, q, end);
                }
            } else {
                return Error.AliasNotFound;
            }
        }
    }

    pub fn nodeLookupByPHandle(self: *Fdt, phandle: u32) !?*Node {
        return self.phandles.get(phandle);
    }

    pub fn nodeLookupByAlias(self: *Fdt, alias_name: []const u8) Error!?*Node {
        if (self.aliases.get(alias_name)) |alias_value| {
            const result = try self.nodeLookupByPath(alias_value);
            return result;
        } else {
            return null;
        }
    }

    pub fn readAliases(self: *Fdt, allocator: Allocator) !void {
        self.aliases = AliasMap.init(allocator);

        const aliases = try self.nodeLookupByPath("/aliases");
        for (aliases.properties.items) |prop| {
            const alias_name = prop.name;
            const alias_value = prop.valueAsString();
            try self.aliases.put(alias_name, alias_value);
        }
    }

    pub fn stringProperty(self: *Fdt, node_path: [:0]const u8, property_name: []const u8) ![:0]const u8 {
        if (try self.nodeLookupByPath(node_path)) |node| {
            if (node.property(property_name)) |prop| {
                return prop.valueAsString();
            } else {
                return Error.NotFound;
            }
        } else {
            return Error.NotFound;
        }
    }

    pub fn property(self: *Fdt, comptime T: type, node_path: [:0]const u8, property_name: []const u8) ![]const T {
        if (try self.nodeLookupByPath(node_path)) |node| {
            if (node.property(property_name)) |prop| {
                return prop.valueAs(T);
            } else {
                return Error.NotFound;
            }
        } else {
            return Error.NotFound;
        }
    }

    pub const TokenType = enum(u32) {
        beginNode = 0x00000001,
        endNode = 0x00000002,
        property = 0x00000003,
        nop = 0x00000004,
        end = 0x00000009,
    };

    pub const Node = struct {
        allocator: Allocator,

        fdt: *Fdt = undefined,
        offset: u64 = undefined,
        name: []const u8 = undefined,
        parent: *Node = undefined,
        children: NodeList,
        properties: PropertyList,

        pub fn create(allocator: Allocator, fdt: *Fdt, offset: u64, name: []const u8) Error!*Node {
            var current_tag_type = try fdt.tagTypeAt(offset);

            if (current_tag_type != .beginNode) {
                return Fdt.Error.IncorrectTag;
            }

            var node: *Node = try allocator.create(Node);
            node.* = Node{
                .allocator = allocator,
                .fdt = fdt,
                .offset = offset,
                .name = name,
                .children = NodeList.init(allocator),
                .properties = PropertyList.init(allocator),
            };
            return node;
        }

        pub fn deinit(self: *Node) void {
            for (self.properties.items) |p| {
                p.deinit();
            }
            self.properties.deinit();

            for (self.children.items) |n| {
                n.deinit();
            }
            self.children.deinit();
            self.allocator.destroy(self);
        }

        pub fn property(self: *Node, name: []const u8) ?*Property {
            for (self.properties.items) |p| {
                if (std.mem.eql(u8, p.name, name)) {
                    return p;
                }
            }
            return null;
        }

        pub fn getChildByName(self: *Node, name: []const u8) ?*Node {
            for (self.children.items) |c| {
                if (std.mem.eql(u8, c.name, name)) {
                    return c;
                }
            }
            return null;
        }

        pub fn lookupChildByPath(self: *Node, path: []const u8, start: usize, end: usize) !*Node {
            if (start == end) {
                return self;
            }

            // pointer to start of current path segment
            var p: usize = start;
            // pointer to end of current path segment
            var q: usize = start;

            // Walk the path, one segment at a time. For each segment,
            // look for a subnode of the current node.

            // Skip the path separator
            while (path[p] == '/') {
                p += 1;
                // If the path ended with '/', we're at the intended
                // node
                if (p == end) {
                    return self;
                }
            }

            // find the next separator, or if none use all of the
            // remaining string as the node name
            q = charIndex('/', path, p) orelse end;

            // starting from the current offset, locate a subnode with
            // the desired name
            if (self.getChildByName(path[p..q])) |child| {
                return child.lookupChildByPath(path, q, end);
            } else {
                return Error.NotFound;
            }
        }

        pub fn propertyFirstValueAs(
            self: *Node,
            comptime Int: type,
            comptime name: []const u8,
            comptime default: Int,
        ) Int {
            if (self.property(name)) |prop| {
                var array = prop.valueAs(Int) catch return 1;
                // TODO: sanity check array should be length 1
                return array[0];
            } else {
                return default;
            }
        }

        pub fn propertyValueAs(
            self: *Node,
            comptime Int: type,
            comptime name: []const u8,
        ) ![]Int {
            if (self.property(name)) |prop| {
                return prop.valueAs(Int);
            } else {
                return Error.NotFound;
            }
        }

        pub fn addressCells(self: *Node) u32 {
            const acells = self.propertyFirstValueAs(u32, "#address-cells", 0);

            if (acells == 0) {
                if (self.parent == self) {
                    return 2;
                } else {
                    return self.parent.addressCells();
                }
            } else {
                return acells;
            }
        }

        pub fn sizeCells(self: *Node) u32 {
            const scells = self.propertyFirstValueAs(u32, "#size-cells", 0);
            if (scells == 0) {
                if (self.parent == self) {
                    return 1;
                } else {
                    return self.parent.sizeCells();
                }
            } else {
                return scells;
            }
        }

        pub fn interruptCells(self: *Node) u32 {
            return self.propertyFirstValueAs(u32, "#interrupt-cells", 1);
        }

        pub fn mboxCells(self: *Node) u32 {
            return self.propertyFirstValueAs(u32, "#mbox-cells", 1);
        }

        pub fn interruptParent(self: *Node) !*Node {
            var iparent_phandle = self.propertyFirstValueAs(u32, "interrupt-parent", 0);
            if (iparent_phandle != 0) {
                return self.fdt.phandles.get(iparent_phandle) orelse Error.NotFound;
            } else {
                return self.parent.interruptParent();
                // return null;
            }
        }

        pub fn translations(self: *Node, prop_name: []const u8) !AddressTranslations {
            if (self.property(prop_name)) |prop| {
                return prop.asTranslations();
            } else {
                return AddressTranslations.init(self.allocator);
            }
        }

        pub fn addressAndLength(self: *Node, prop_name: []const u8) !AddressAndLength {
            if (self.property(prop_name)) |prop| {
                return prop.addressAndLength();
            } else {
                return Error.NotFound;
            }
        }

        pub fn interrupts(self: *Node) !struct { u32, []u32 } {
            const iparent = try self.interruptParent();
            const icells = iparent.interruptCells();
            const ints = try self.propertyValueAs(u32, "interrupts");
            return .{ icells, ints };
        }
    };

    pub const Property = struct {
        allocator: Allocator,
        offset: u64 = undefined,
        value_offset: u64 = undefined,
        value_len: usize = undefined,
        name: []u8 = undefined,
        owner: *Node = undefined,

        pub fn create(allocator: Allocator, owner: *Node, offset: u64, name: []u8, value_offset: u64, value_len: usize) Error!*Property {
            var prop = try allocator.create(Property);
            prop.* = Property{
                .allocator = allocator,
                .offset = offset,
                .owner = owner,
                .name = name,
                .value_offset = value_offset,
                .value_len = value_len,
            };
            return prop;
        }

        pub fn deinit(self: *Property) void {
            self.allocator.destroy(self);
        }

        // Caller owns the returned slice.
        pub fn valueAs(self: *Property, comptime T: anytype) ![]T {
            const value_start = self.owner.fdt.struct_base + self.value_offset;
            const value_ptr: [*]T = @ptrFromInt(value_start);
            const value_count = self.value_len / @sizeOf(T);
            const value_slice = value_ptr[0..value_count];

            const list_type = ArrayList(T);
            var native_value_list = list_type.init(self.allocator);
            defer native_value_list.deinit();

            for (value_slice) |v| {
                try native_value_list.append(nativeByteOrder(v));
            }

            return native_value_list.toOwnedSlice();
        }

        pub fn valueAsString(self: *Property) []const u8 {
            const value_start = self.owner.fdt.struct_base + self.value_offset;
            const value_ptr: [*]u8 = @ptrFromInt(value_start);
            return @ptrCast(value_ptr[0 .. self.value_len - 1]);
        }

        pub fn addressAndLength(self: *Property) !AddressAndLength {
            var raw = self.valueAs(u32) catch return Error.ValueUnavailable;
            const acells = self.owner.addressCells();
            const scells = self.owner.sizeCells();
            const address: u64 = cellsAs(raw[0..acells]);
            const length: u64 = cellsAs(raw[acells..(acells + scells)]);
            return .{ address, length };
        }

        pub fn asTranslations(self: *Property) !AddressTranslations {
            var raw_ranges = self.valueAs(u32) catch return Error.ValueUnavailable;
            var translations = AddressTranslations.init(self.allocator);

            var parent_acells = if (self.owner.parent != undefined)
                self.owner.parent.addressCells()
            else
                1;
            var child_acells = self.owner.addressCells();
            var scells = self.owner.sizeCells();
            var entry_len = parent_acells + child_acells + scells;

            if (0 != raw_ranges.len % entry_len) {
                kwarn(@src(), "value length {d}, expected {d}\n", .{ raw_ranges.len, entry_len });
                return Error.ValueWrongLength;
            }

            var idx: usize = 0;
            while (idx < raw_ranges.len) {
                var child_addr = cellsAs(raw_ranges[idx..(idx + child_acells)]);
                idx += child_acells;
                var parent_addr = cellsAs(raw_ranges[idx..(idx + parent_acells)]);
                idx += parent_acells;
                var len = cellsAs(raw_ranges[idx..(idx + scells)]);
                idx += scells;

                const tln = try self.allocator.create(AddressTranslation);
                AddressTranslation.init(tln, parent_addr, child_addr, len);
                try translations.append(tln);
            }
            return translations;
        }
    };

    pub fn parse(self: *Fdt, allocator: Allocator) !*Node {
        var parents = NodeList.init(allocator);
        defer parents.deinit();

        var current_tag_offset: usize = 0;

        var current_tag_type = try self.tagTypeAt(current_tag_offset);
        if (current_tag_type != .beginNode) {
            return Fdt.Error.IncorrectTag;
        }

        // walk the tags.
        while (current_tag_offset < self.struct_size) {
            // std.debug.print("{x:0>5} {s}\n", .{ current_tag_offset, @tagName(current_tag_type) });

            switch (current_tag_type) {
                .beginNode => {
                    const node_offset = current_tag_offset;

                    // locate the name
                    current_tag_offset += tag_size;
                    var p: [*]u8 = @ptrCast(self.ptrFromOffset(u8, current_tag_offset));
                    current_tag_offset += 1;
                    var i: usize = 0;
                    while (p[i] != 0) : (i += 1) {}
                    current_tag_offset += i;
                    const node_name = p[0..i];

                    //   create new Node object with that as offset
                    const node = try Node.create(allocator, self, node_offset, node_name);

                    //   add it as a child to the Node on top of `parents`
                    if (parents.getLastOrNull()) |current_parent| {
                        node.parent = current_parent;
                        try current_parent.children.append(node);
                    } else {
                        // this is the very first node.
                        // it is the root
                        node.name = "/";
                        // it has no parent so make it it's own parent
                        node.parent = node;
                    }

                    // std.debug.print(">>\n", .{});

                    //   push the new Node onto parents
                    try parents.append(node);
                },
                .endNode => {
                    // advance offset past the tag. the tag has no body.
                    current_tag_offset += tag_size;

                    // std.debug.print("<<\n", .{});

                    //   pop the top of `parents`
                    if (parents.popOrNull()) |current_node| {
                        if (parents.items.len == 0) {
                            // if the stack is now empty, we've reached
                            // the final .endNode, return the root node
                            return current_node;
                        }
                    } else {
                        // we've seen more .endNode tags than .beginNode
                        return Fdt.Error.BadContents;
                    }
                },
                .end => {
                    return Fdt.Error.BadContents;
                },
                .property => {
                    const prop_offset = current_tag_offset;

                    current_tag_offset += tag_size;
                    const value_len = self.valueAtOffset(u32, current_tag_offset);

                    current_tag_offset += tag_size;
                    const prop_name_idx = self.valueAtOffset(u32, current_tag_offset);

                    current_tag_offset += tag_size;
                    const value_offset = current_tag_offset;

                    current_tag_offset += value_len;

                    const current_parent = parents.getLastOrNull();

                    if (current_parent == null) {
                        return Error.BadContents;
                    }

                    const prop_name = self.stringAt(prop_name_idx);
                    const prop = try Property.create(allocator, current_parent.?, prop_offset, prop_name, value_offset, value_len);

                    try current_parent.?.properties.append(prop);

                    // if this property is a phandle, add the current
                    // node to the tree's map from phandle -> *Node
                    if (std.mem.eql(u8, prop_name, "phandle")) {
                        const phandle_value = self.valueAtOffset(u32, value_offset);
                        try self.phandles.put(phandle_value, current_parent.?);
                    }
                },
                inline else => current_tag_offset += tag_size,
            }

            current_tag_offset = std.mem.alignForward(usize, current_tag_offset, tag_size);
            current_tag_type = try self.tagTypeAt(current_tag_offset);
        }

        // We've walked past the end of the struct but didn't see matching
        // .endNode tag
        return Error.BadContents;
    }

    pub fn tagTypeAt(self: *Fdt, tag_offset: usize) !TokenType {
        if (0 != (tag_offset % tag_size)) {
            return Error.BadTagAlignment;
        }

        var tag_ptr: *u32 = self.ptrFromOffset(u32, tag_offset);
        var tag: u32 = nativeByteOrder(tag_ptr.*);
        switch (tag) {
            0x00000001 => return .beginNode,
            0x00000002 => return .endNode,
            0x00000003 => return .property,
            0x00000004 => return .nop,
            0x00000009 => return .end,
            else => {
                // std.debug.print("At offset {x}, found {x} instead of a device tree tag\n", .{ tag_offset, tag });
                return Error.NoTagAtOffset;
            },
        }
    }

    inline fn stringAt(self: *Fdt, string_offset: usize) []u8 {
        const string_addr = self.strings_base + string_offset;
        const string_ptr: [*]u8 = @ptrFromInt(string_addr);
        var len: usize = 0;
        while (string_ptr[len] != 0) {
            len += 1;
        }
        return string_ptr[0..len];
    }

    inline fn ptrFromOffset(self: *Fdt, comptime T: type, offset: usize) *T {
        // var base: usize = self.struct_base + offset;
        return @ptrFromInt(self.struct_base + offset);
    }

    inline fn valueAtOffset(self: *Fdt, comptime T: type, offset: usize) T {
        const p: *T = self.ptrFromOffset(T, offset);
        return nativeByteOrder(p.*);
    }
};

pub inline fn nativeByteOrder(v: anytype) @TypeOf(v) {
    return std.mem.bigToNative(@TypeOf(v), v);
}

fn charIndex(ch: u8, s: []const u8, from: usize) ?usize {
    for (from..s.len) |i| {
        if (s[i] == ch) {
            return i;
        }
    }
    return null;
}

test "locate node and property by path" {
    const print = std.debug.print;
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    const fdt_path = "test/resources/fdt.bin";
    const stat = try std.fs.cwd().statFile(fdt_path);
    var buffer = try std.fs.cwd().readFileAlloc(std.testing.allocator, fdt_path, stat.size);
    defer std.testing.allocator.free(buffer);

    var fdt = Fdt{};
    try fdt.initFromPointer(std.testing.allocator, @intFromPtr(buffer.ptr));
    defer fdt.deinit();

    print("\n", .{});

    var devtree_root = fdt.root_node;

    try expectEqualStrings("", devtree_root.name);

    var found = try fdt.nodeLookupByPath("/thermal-zones/cpu-thermal/cooling-maps");
    try expect(found != null);

    var soc = try fdt.nodeLookupByPath("/soc");
    try expectEqual(soc.?.property("no-such-thing"), null);

    const soc_compat = soc.?.property("compatible");
    const expected_compat_value = [_]u8{ 's', 'i', 'm', 'p', 'l', 'e', '-', 'b', 'u', 's', 0 };
    try expectEqualStrings(&expected_compat_value, soc_compat.?.valueAs(u8));
    try expectEqualStrings(expected_compat_value[0 .. expected_compat_value.len - 1], soc_compat.?.valueAsString());

    const soc_phandle = soc.?.property("phandle");
    const expected_phandle_value = [_]u32{0x3e};

    const phandle_value = soc_phandle.?.valueAs(u32);
    for (phandle_value, 0..) |actual_word, i| {
        try expectEqual(expected_phandle_value[i], nativeByteOrder(actual_word));
    }

    const expected_dma_ranges = [_]u32{ 0xc0000000, 0x00, 0x3f000000, 0x7e000000, 0x3f000000, 0x1000000 };
    const soc_dma_ranges = soc.?.property("dma-ranges");
    const dma_ranges_value = soc_dma_ranges.?.valueAs(u32);
    for (dma_ranges_value, 0..) |actual_word, i| {
        try expectEqual(expected_dma_ranges[i], nativeByteOrder(actual_word));
    }

    const reserved_memory = try fdt.nodeLookupByPath("/reserved-memory");
    const reserved_memory_ranges = reserved_memory.?.property("ranges");
    try expect(reserved_memory_ranges != null);
    try expect(reserved_memory_ranges.?.valueAs(u32).len == 0);

    const timer = try fdt.nodeLookupByPath("/timer");
    const timer_interrupt_parent = timer.?.property("interrupt-parent");
    var timer_interrupt_parent_value = timer_interrupt_parent.?.valueAs(u32)[0];
    timer_interrupt_parent_value = nativeByteOrder(timer_interrupt_parent_value);
    const t_i_p = try fdt.nodeLookupByPHandle(timer_interrupt_parent_value);
    try expectEqualStrings(t_i_p.?.name, "local_intc@40000000");

    const serial = try fdt.nodeLookupByPath("/soc/serial@7e201000");
    const serial_compat = serial.?.property("compatible");
    var serial_compat_values = std.mem.splitAny(u8, serial_compat.?.valueAsString(), &[_]u8{0});
    try expectEqualStrings("arm,pl011", serial_compat_values.next().?);
    try expectEqualStrings("arm,primecell", serial_compat_values.next().?);
}

test "locate nodes via aliases" {
    const expect = std.testing.expect;

    const fdt_path = "test/resources/fdt.bin";
    const stat = try std.fs.cwd().statFile(fdt_path);
    var buffer = try std.fs.cwd().readFileAlloc(std.testing.allocator, fdt_path, stat.size);
    defer std.testing.allocator.free(buffer);

    var fdt = Fdt{};
    try fdt.initFromPointer(std.testing.allocator, @intFromPtr(buffer.ptr));
    defer fdt.deinit();

    const serial0_by_path = try fdt.nodeLookupByPath("/soc/serial@7e215040");
    try expect(serial0_by_path != null);

    const serial0 = try fdt.nodeLookupByPath("serial0");
    try expect(serial0 != null);
    try expect(serial0 == serial0_by_path);
}
