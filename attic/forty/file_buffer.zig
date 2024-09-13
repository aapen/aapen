const Self = @This();

source: []const u8 = undefined,
position: usize = 0,

pub fn init(source: []const u8) Self {
    return .{
        .source = source,
        .position = 0,
    };
}

pub fn read(self: *Self) u8 {
    if (self.position >= self.source.len) {
        return 0;
    } else {
        const next = self.source[self.position];
        self.position += 1;
        return next;
    }
}

pub fn hasMore(self: *Self) bool {
    return self.position < self.source.len;
}
