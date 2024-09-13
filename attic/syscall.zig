const std = @import("std");
const root = @import("root");

const Forth = @import("forty/forth.zig");
const Memory = @import("forty/memory.zig");
const Header = Memory.Header;
const ForthError = @import("forty/errors.zig").ForthError;

// ----------------------------------------------------------------------
// Prototype for syscall target
// ----------------------------------------------------------------------

pub const Fptr = *const fn ([]const u64) u64;

// ----------------------------------------------------------------------
// Call table
// ----------------------------------------------------------------------

const Syscall = struct {
    name: []const u8,
    fptr: ?Fptr,
    argcount: u8,
};

fn S(name: []const u8, f: Fptr, arity: u8) Syscall {
    return .{ .name = name, .fptr = f, .argcount = arity };
}

const syscalls: []const Syscall = &[_]Syscall{
    S("", sysDummy, 0),
    S("emit", sysEmit, 1),
};

const syscall_max: u32 = syscalls.len;

// ----------------------------------------------------------------------
// Dispatcher
// ----------------------------------------------------------------------

pub fn wordSyscall(forth: *Forth, _: *Header) ForthError!void {
    var stack = &forth.stack;

    const syscall_number = try stack.pop();

    if (syscall_number > syscall_max - 1) {
        try stack.push(0);
        return ForthError.BadOperation;
    }

    const call = syscalls[syscall_number];

    const fptr = call.fptr orelse {
        try stack.push(0);
        return ForthError.BadOperation;
    };

    const arg_count = call.argcount;

    if (arg_count > stack.depth()) {
        return ForthError.UnderFlow;
    }

    const first_arg = stack.depth() - arg_count;
    const args = stack.items()[first_arg..(first_arg + arg_count)];
    const ret = fptr(args);

    try stack.dropN(arg_count);
    try stack.push(ret);
}

// ----------------------------------------------------------------------
// Stubs where the syscall signature is wrong (these should be
// temporary)
// ----------------------------------------------------------------------

fn sysDummy(_: []const u64) u64 {
    return 0;
}

fn sysEmit(args: []const u64) u64 {
    const a = args[0];
    root.interpreter.console.putc(@truncate(a));
    return 0;
}
