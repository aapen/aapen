const std = @import("std");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const memory = @import("memory.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

inline fn invokeF(comptime FuncT: type, comptime pushResult: bool, forth: *Forth, _: [*]u64, _: u64, _: *Header) ForthError!u64 {
    const f = try forth.stack.pop();
    const func: FuncT = @ptrFromInt(f);

    const FuncType = @typeInfo(FuncT).Pointer.child;
    const info = @typeInfo(FuncType).Fn;
    const nParams: u64 = info.params.len;

    var result: u64 = 0;
    switch(nParams) {
        0 => {
            if (pushResult) {
               result = func();
            } else {
               func();
            }
        },
        1 => {
            const arg1 = try forth.stack.pop();
            if (pushResult) {
               result = func(arg1);
            } else {
               func(arg1);
            }
        },
        2 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            if (pushResult) result = func(arg1, arg2);
            if (pushResult){
               result = func(arg1, arg2);
            } else {
               func(arg1, arg2);
            }
        },
        3 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            if (pushResult){
               result = func(arg1, arg2, arg3);
            } else {
               func(arg1, arg2, arg3);
            }
        },
        else => {
            try forth.print("Can't handle a function of {} args {x}\n", .{nParams, func});
            return ForthError.BadOperation;
        },
    }

    if (pushResult) {
        try forth.stack.push(result);
    }
    return 0;
}

/// fAddr -- : Call a no args function, no return value.
pub fn wordInvoke(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn()void, false, forth, body, offset, header);
}

/// fAddr -- : Call a 1 arg function, no return value.
pub fn wordInvokeU(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(u64)void, false, forth, body, offset, header);
}

/// fAddr -- : Call a 2 arg function, no return value.
pub fn wordInvokeUU(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(u64, u64)void, false, forth, body, offset, header);
}

/// fAddr -- : Call a 3 arg function, no return value.
pub fn wordInvokeUUU(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(u64, u64, u64)void, false, forth, body, offset, header);
}

/// fAddr -- result : Call a no args function, push return value.
pub fn wordInvokeR(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn() u64, true, forth, body, offset, header);
}

/// u64 fAddr -- result : Call a 1 argument function, push return value.
pub fn wordInvokeUR(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(a: u64) u64, true, forth, body, offset, header);
}

/// u64 u64 fAddr -- result : Call a 2 argument function, push return value.
pub fn wordInvokeUUR(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(a: u64, b: u64) u64, true, forth, body, offset, header);
}

/// u64 u64 u64 fAddr -- result : Call a 3 argument function, push return value.
pub fn wordInvokeUUUR(forth: *Forth, body: [*]u64, offset: u64, header: *Header) ForthError!u64 {
    return invokeF(*const fn(a: u64, b: u64, c: u64) u64, true, forth, body, offset, header);
}

fn double_u64(a: u64) u64 {
    return a*2;
}


fn add_u64(a: u64, b: u64) u64 {
    return a+b;
}


fn add_3(a: u64, b: u64, c: u64) u64 {
    return a+b+c;
}

fn print_msg(f: u64) void {
    var forth: *Forth = @ptrFromInt(f);
    try forth.print("A message!\n", .{});
}

pub fn defineInterop(forth: *Forth) !void {
    // Some native functions for testing.
    try forth.defineConstant("double-u64", @intFromPtr(&double_u64));
    try forth.defineConstant("add-u64", @intFromPtr(&add_u64));
    try forth.defineConstant("add-3", @intFromPtr(&add_3));
    try forth.defineConstant("print-msg", @intFromPtr(&print_msg));

    // Variations on invoke.
    _ = try forth.definePrimitiveDesc("invoke-r", "addr -- result : invoke a no args function", &wordInvokeUR, 0);
    _ = try forth.definePrimitiveDesc("invoke-ur", "n addr -- result : invoke a 1 arg function", &wordInvokeUR, 0);
    _ = try forth.definePrimitiveDesc("invoke-uur", "n n addr -- result : invoke a 2 arg function", &wordInvokeUUR, 0);
    _ = try forth.definePrimitiveDesc("invoke-uuur", "n n n addr -- result : invoke a 2 arg function", &wordInvokeUUUR, 0);

    _ = try forth.definePrimitiveDesc("invoke", "n addr --  : invoke a 0 arg function, void", &wordInvoke, 0);
    _ = try forth.definePrimitiveDesc("invoke-u", "n addr --  : invoke a 1 arg function, void", &wordInvokeU, 0);
    _ = try forth.definePrimitiveDesc("invoke-uu", "n addr --  : invoke a 2 arg function, void", &wordInvokeUU, 0);
    _ = try forth.definePrimitiveDesc("invoke-uuu", "n addr --  : invoke a 3 arg function, void", &wordInvokeUUU, 0);
}
