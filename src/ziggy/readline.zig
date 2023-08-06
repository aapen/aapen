pub const Error = error{
    InputError,
};

pub const Readline = *const fn (context: *anyopaque, prompt: []const u8, buffer: []u8) Error!usize;
