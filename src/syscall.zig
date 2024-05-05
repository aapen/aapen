const std = @import("std");
const root = @import("root");

const Forth = @import("forty/forth.zig").Forth;
const Header = @import("forty/memory.zig").Header;
const ForthError = @import("forty/errors.zig").ForthError;

pub fn defineModule(forth: *Forth) !void {
    // TODO - once we have a better suite of syscalls, remove all the
    // 'defineModule' calls
    _ = try forth.definePrimitiveDesc("syscall", "... n -- n : invoke syscall n", &wordSyscall, false);
}

// ----------------------------------------------------------------------
// Prototype for syscall target
// ----------------------------------------------------------------------

pub const Fptr = *const fn ([]const u64) u64;

// ----------------------------------------------------------------------
// Call table
// ----------------------------------------------------------------------

const Syscall = struct {
    name: []const u8,
    fptr: Fptr,
    argcount: u8,

    fn fromSpec(tuple: struct { u16, []const u8, Fptr, u8 }) Syscall {
        return .{
            .name = tuple[1],
            .fptr = tuple[2],
            .argcount = tuple[3],
        };
    }
};

const syscall_specs = .{
    .{ 1, "emit", sysEmit, 1 },
};

const syscalls: []Syscall = init: {
    var initial_value: [syscall_specs.len + 1]Syscall = undefined;
    for (syscall_specs) |s| {
        initial_value[s[0]] = Syscall.fromSpec(s);
    }
    break :init &initial_value;
};

// ----------------------------------------------------------------------
// Dispatcher
// ----------------------------------------------------------------------

pub fn wordSyscall(forth: *Forth, _: *Header) ForthError!void {
    var stack = forth.stack;

    const syscall_number = try stack.pop();

    // TODO verify syscall_number is in range
    // TODO verify argcount is available on stack

    const call = syscalls[syscall_number];
    const arg_count = call.argcount;
    const first_arg = stack.depth() - arg_count;
    const args = stack.items()[first_arg..(first_arg + arg_count)];
    const fptr = call.fptr;
    const ret = fptr(args);
    try stack.dropN(arg_count);
    try stack.push(ret);
}

// ----------------------------------------------------------------------
// Stubs where the syscall signature is wrong (these should be
// temporary)
// ----------------------------------------------------------------------

fn sysEmit(args: []const u64) u64 {
    _ = args;

    root.log.info(@src(), "here", .{});

    return 0;
}
