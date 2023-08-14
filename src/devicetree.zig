const std = @import("std");
const root = @import("root");

// This symbol is defined in boot.S.
// At boot time its value will be supplied by the firmware, which will
// point it at some memory.
pub extern var __fdt_address: usize;

pub const Fdt = struct {
    const Self = @This();

    // These constants come from the device tree specification.
    // See https://github.com/devicetree-org/devicetree-specification
    const compatible_version = 16;
    const magic_value = 0xd00dfeed;

    // Member variables will be in native byte order
    struct_base: usize = undefined,
    strings_base: usize = undefined,

    pub const Error = error{
        NotFound,
        BadVersion,
        BadTagAlignment,
        NoTagAtOffset,
    };

    /// Note: when reading from __fdt_address, these will all be
    /// big-endian
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

    pub fn init(self: *Self) !void {
        var h: *Header = @ptrFromInt(__fdt_address);

        if (nativeByteOrder(h.magic) != magic_value) {
            return Error.NotFound;
        }

        if (nativeByteOrder(h.last_compatible_version) < compatible_version) {
            return Error.BadVersion;
        }

        // if those passed, we have a good blob.
        // from here, self.struct_base and self.strings_base will be
        // pre-added and in native byte order
        self.struct_base = __fdt_address + nativeByteOrder(h.off_dt_struct);
        self.strings_base = __fdt_address + nativeByteOrder(h.off_dt_strings);
    }

    /// Find a node that matches the given path. On success, return
    /// its offset (in bytes). If not found, returns null.
    pub fn nodeLookupByPath(self: *Self, path: [:0]const u8) !?usize {
        // TODO: handle aliases

        // byte offset from start of dt_struct
        var current_node_offset: ?usize = 0;
        // pointer to start of current path segment
        var p: usize = 0;
        // pointer to end of current path segment
        var q: usize = 0;
        var end: usize = path.len;

        // Walk the path, one segment at a time. For each segment,
        // look for a subnode of the current node.
        while (p < end and (current_node_offset != null)) {
            // Skip the path separator
            while (path[p] == '/') {
                p += 1;
                // If the path ended with '/', we're at the intended
                // node
                if (p == end) {
                    return current_node_offset;
                }
            }

            // find the next separator, or if none use all of the
            // remaining string as the node name
            q = charIndex('/', path, p) orelse end;

            // starting from the current offset, locate a subnode with
            // the desired name
            if (try self.subnodeOffsetLookupByName(current_node_offset.?, path, p, q)) |next_node_offset| {
                current_node_offset = next_node_offset;
            } else {
                return null;
            }

            // Advance pointer to next segment
            p = q;
        }
        return current_node_offset;
    }

    fn subnodeOffsetLookupByName(self: *Self, starting_node_offset: usize, path: [:0]const u8, start: usize, end: usize) !?usize {
        var current_node_offset = starting_node_offset;

        // Advance through nested pairs of .beginNode and .endNode
        // tokens looking for a .beginNode with matching name.
        while (!(try self.nodeNameEql(current_node_offset, path, start, end))) {
            // Advance to the next .beginNode token
            if (try self.nextNode(current_node_offset)) |next_node_offset| {
                current_node_offset = next_node_offset;
            } else {
                // there wasn't another sibling node, the desired name
                // was not found
                return null;
            }
        }

        return current_node_offset;
    }

    pub fn nodeNameEql(self: *Self, current_node_offset: usize, path: [*:0]const u8, start: usize, end: usize) !bool {
        var tag_type = try self.tagTypeAt(current_node_offset);

        if (tag_type != .beginNode) {
            return Error.BadTagAlignment;
        }

        var node_name: [*]u8 = @ptrFromInt(self.struct_base + current_node_offset + tag_size);

        for (0..end - start) |i| {
            if (path[start + i] != node_name[i]) {
                return false;
            }
        }
        return true;
    }

    inline fn tagTypeAt(self: *Self, tag_offset: usize) !TokenType {
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
            else => return Error.NoTagAtOffset,
        }
    }

    inline fn stringAt(self: *Self, string_offset: usize) [*]u8 {
        var string_addr = self.strings_base + string_offset;
        return @ptrFromInt(string_addr);
    }

    /// Advance the offset to the next node at the current nesting level
    fn nextNode(self: *Self, starting_offset: usize) !?usize {
        var current_tag_offset: usize = starting_offset;
        var current_tag_type = try self.tagTypeAt(current_tag_offset);

        // starting from a .beginNode tag
        if (current_tag_type != .beginNode) {
            return Error.BadTagAlignment;
        }

        var next_tag_offset: usize = current_tag_offset;
        var tag: TokenType = undefined;

        // advance past the .beginNode tag
        tag = try self.nextTag(current_tag_offset, &next_tag_offset);

        // start with nesting level 1 because we need to find the end
        // of the current node, so we expect one more .endNode than we
        // see .beginNode tags
        var nesting_level: usize = 1;

        // find the next .beginNode tags _after_ the .endNode for the
        // node we started in (i.e. nesting_level must be zero).
        // note that there may be .nop tags between the .endNode and
        // the next .beginNode
        while (nesting_level > 0 and tag != .beginNode) {
            switch (tag) {
                .property, .nop => {
                    // simply skip these
                },
                .beginNode => {
                    // descend into a nested node
                    nesting_level += 1;
                },
                .endNode => {
                    // if we're already at level 0, then we've reached
                    // the end of the _parent_ node and have not found
                    // a sibling
                    if (nesting_level == 0) {
                        return null;
                    }
                    // ascend from a level of nesting
                    nesting_level -= 1;
                },
                .end => {
                    // We've reached the end of the entire device tree
                    return null;
                },
            }

            // advance to the next tag
            current_tag_offset = next_tag_offset;
            tag = try self.nextTag(current_tag_offset, &next_tag_offset);
        }
        return next_tag_offset;
    }

    const tag_size: usize = @sizeOf(u32);

    inline fn ptrFromOffset(self: *Self, comptime T: type, offset: usize) *T {
        // var base: usize = self.struct_base + offset;
        return @ptrFromInt(self.struct_base + offset);
    }

    // Caution: side effects
    // this function updates *next_tag_offset to point the the next
    // tag _after_ the one that starting_tag_offset points at.
    // It return the type of the _next_ tag
    fn nextTag(self: *Self, starting_tag_offset: usize, next_tag_offset: *usize) !TokenType {
        var current_tag_offset = starting_tag_offset;

        var tag_type = try self.tagTypeAt(current_tag_offset);
        current_tag_offset += tag_size;

        switch (tag_type) {
            .beginNode => {
                // skip name
                var p: [*]u8 = @ptrCast(self.ptrFromOffset(u8, current_tag_offset));
                current_tag_offset += 1;
                var i: usize = 0;
                while (p[i] != 0) : (i += 1) {}
                current_tag_offset += i;
            },
            .property => {
                var lenp: *u32 = self.ptrFromOffset(u32, current_tag_offset);
                var len: u32 = nativeByteOrder(lenp.*);
                // skip the name index (u32), prop len (u32), and
                // value (however many bytes the prop len said)
                current_tag_offset += (tag_size * 2) + len;
            },
            .end, .endNode, .nop => {},
        }
        next_tag_offset.* = std.mem.alignForward(usize, current_tag_offset, tag_size);
        return self.tagTypeAt(next_tag_offset.*);
    }

    fn charIndex(ch: u8, s: [:0]const u8, from: usize) ?usize {
        for (from..s.len) |i| {
            if (s[i] == ch) {
                return i;
            }
        }
        return null;
    }
};

pub const TokenType = enum(u32) {
    beginNode = 0x00000001,
    endNode = 0x00000002,
    property = 0x00000003,
    nop = 0x00000004,
    end = 0x00000009,
};

inline fn read(comptime Int: type, addr: usize) Int {
    var ptr: *Int = @ptrFromInt(addr);
    return nativeByteOrder(ptr.*);
}

inline fn nativeByteOrder(v: u32) u32 {
    return std.mem.bigToNative(u32, v);
}
