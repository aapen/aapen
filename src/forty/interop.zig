const std = @import("std");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const memory = @import("memory.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

fn invokeF(comptime FuncT: type, comptime pushResult: bool, forth: *Forth) ForthError!void {
    const f = try forth.stack.pop();
    const func: FuncT = @ptrFromInt(f);

    const FuncType = @typeInfo(FuncT).Pointer.child;
    const info = @typeInfo(FuncType).Fn;
    const nParams: u64 = info.params.len;

    var result: u64 = 0;
    switch (nParams) {
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
            if (pushResult) {
                result = func(arg1, arg2);
            } else {
                func(arg1, arg2);
            }
        },
        3 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            if (pushResult) {
                result = func(arg1, arg2, arg3);
            } else {
                func(arg1, arg2, arg3);
            }
        },
        4 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            const arg4 = try forth.stack.pop();
            if (pushResult) {
                result = func(arg1, arg2, arg3, arg4);
            } else {
                func(arg1, arg2, arg3, arg4);
            }
        },
        5 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            const arg4 = try forth.stack.pop();
            const arg5 = try forth.stack.pop();
            if (pushResult) {
                result = func(arg1, arg2, arg3, arg4, arg5);
            } else {
                func(arg1, arg2, arg3, arg4, arg5);
            }
        },
        6 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            const arg4 = try forth.stack.pop();
            const arg5 = try forth.stack.pop();
            const arg6 = try forth.stack.pop();
            if (pushResult) {
                result = func(arg1, arg2, arg3, arg4, arg5, arg6);
            } else {
                func(arg1, arg2, arg3, arg4, arg5, arg6);
            }
        },
        7 => {
            const arg1 = try forth.stack.pop();
            const arg2 = try forth.stack.pop();
            const arg3 = try forth.stack.pop();
            const arg4 = try forth.stack.pop();
            const arg5 = try forth.stack.pop();
            const arg6 = try forth.stack.pop();
            const arg7 = try forth.stack.pop();
            if (pushResult) {
                result = func(arg1, arg2, arg3, arg4, arg5, arg6, arg7);
            } else {
                func(arg1, arg2, arg3, arg4, arg5, arg6, arg7);
            }
        },
        else => {
            try forth.print("Can't handle a function of {} args {x}\n", .{ nParams, func });
            return ForthError.BadOperation;
        },
    }

    if (pushResult) {
        try forth.stack.push(result);
    }
}

/// fAddr -- : Call a no args function, no return value.
pub fn wordInvoke0(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn () void, false, forth);
}

/// u64 fAddr -- : Call a 1 arg function, no return value.
pub fn wordInvoke1(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64) void, false, forth);
}

/// u64 u64 fAddr -- : Call a 2 arg function, no return value.
pub fn wordInvoke2(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64) void, false, forth);
}

/// u64 u64 u64 fAddr -- : Call a 3 arg function, no return value.
pub fn wordInvoke3(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64) void, false, forth);
}

/// u64 u64 u64 u64 fAddr -- : Call a 4 arg function, no return value.
pub fn wordInvoke4(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64) void, false, forth);
}

/// u64 u64 u64 u64 u64 fAddr -- : Call a 5 arg function, no return value.
pub fn wordInvoke5(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64) void, false, forth);
}

/// u64 u64 u64 u64 u64 u64 fAddr -- : Call a 6 arg function, no return value.
pub fn wordInvoke6(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64, u64) void, false, forth);
}

/// u64 u64 u64 u64 u64 u64 u64 fAddr -- : Call a 7 arg function, no return value.
pub fn wordInvoke7(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64, u64, u64) void, false, forth);
}

/// fAddr -- result : Call a no args function, push return value.
pub fn wordInvoke0R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn () u64, true, forth);
}

/// u64 fAddr -- result : Call a 1 argument function, push return value.
pub fn wordInvoke1R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (a: u64) u64, true, forth);
}

/// u64 u64 fAddr -- result : Call a 2 argument function, push return value.
pub fn wordInvoke2R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (a: u64, b: u64) u64, true, forth);
}

/// u64 u64 u64 fAddr -- result : Call a 3 argument function, push return value.
pub fn wordInvoke3R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (a: u64, b: u64, c: u64) u64, true, forth);
}

/// u64 u64 u64 u64 fAddr -- result : Call a 4 arg function, push return value.
pub fn wordInvoke4R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64) u64, true, forth);
}

/// u64 u64 u64 u64 u64 fAddr -- result : Call a 5 arg function, push return value.
pub fn wordInvoke5R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64) u64, true, forth);
}

/// u64 u64 u64 u64 u64 u64 fAddr -- result : Call a 6 arg function, push return value.
pub fn wordInvoke6R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64, u64) u64, true, forth);
}

/// u64 u64 u64 u64 u64 u64 u64 fAddr -- result : Call a 7 arg function, push return value.
pub fn wordInvoke7R(forth: *Forth, _: *Header) ForthError!void {
    return invokeF(*const fn (u64, u64, u64, u64, u64, u64, u64) u64, true, forth);
}

fn double_u64(a: u64) u64 {
    return a * 2;
}

fn add_u64(a: u64, b: u64) u64 {
    return a + b;
}

fn add_3(a: u64, b: u64, c: u64) u64 {
    return a + b + c;
}

fn add_4(a: u64, b: u64, c: u64, d: u64) u64 {
    return a + b + c + d;
}

fn add_5(a: u64, b: u64, c: u64, d: u64, e: u64) u64 {
    return a + b + c + d + e;
}

fn add_6(a: u64, b: u64, c: u64, d: u64, e: u64, f: u64) u64 {
    return a + b + c + d + e + f;
}

fn print_msg(f: u64) !void {
    var forth: *Forth = @ptrFromInt(f);
    try forth.print("A message!\n", .{});
}

pub fn defineInterop(forth: *Forth) !void {
    // Some native functions for testing.
    try forth.defineConstant("double-u64", @intFromPtr(&double_u64));
    try forth.defineConstant("add-u64", @intFromPtr(&add_u64));
    try forth.defineConstant("add-3", @intFromPtr(&add_3));
    try forth.defineConstant("add-4", @intFromPtr(&add_4));
    try forth.defineConstant("add-5", @intFromPtr(&add_5));
    try forth.defineConstant("add-6", @intFromPtr(&add_6));
    try forth.defineConstant("print-msg", @intFromPtr(&print_msg));

    // Variations on invoke.
    _ = try forth.definePrimitiveDesc("invoke-0r", "addr -- result : invoke a 0 arg fn, push return", &wordInvoke0R, false);
    _ = try forth.definePrimitiveDesc("invoke-1r", "n addr -- result : invoke a 1 arg fn, push return", &wordInvoke1R, false);
    _ = try forth.definePrimitiveDesc("invoke-2r", "n n addr -- result : invoke a 2 arg fn, push return", &wordInvoke2R, false);
    _ = try forth.definePrimitiveDesc("invoke-3r", "n n n addr -- result : invoke a 3 arg fn, push return", &wordInvoke3R, false);
    _ = try forth.definePrimitiveDesc("invoke-4r", "n n n n addr -- result : invoke a 4 arg fn, push return", &wordInvoke4R, false);
    _ = try forth.definePrimitiveDesc("invoke-5r", "n n n n n addr -- result : invoke a 5 arg fn, push return", &wordInvoke5R, false);
    _ = try forth.definePrimitiveDesc("invoke-6r", "n n n n n n addr -- result : invoke a 6 arg fn, push return", &wordInvoke6R, false);
    _ = try forth.definePrimitiveDesc("invoke-7r", "n n n n n n n addr -- result : invoke a 7 arg fn, push result", &wordInvoke7R, false);

    _ = try forth.definePrimitiveDesc("invoke-0", "addr --  : invoke a 0 arg void fn", &wordInvoke0, false);
    _ = try forth.definePrimitiveDesc("invoke-1", "n addr --  : invoke a 1 arg void fn", &wordInvoke1, false);
    _ = try forth.definePrimitiveDesc("invoke-2", "n n addr --  : invoke a 2 arg void fn", &wordInvoke2, false);
    _ = try forth.definePrimitiveDesc("invoke-3", "n n n addr --  : invoke a 3 arg void fn", &wordInvoke3, false);
    _ = try forth.definePrimitiveDesc("invoke-4", "n n n n addr --  : invoke a 4 arg void fn", &wordInvoke4, false);
    _ = try forth.definePrimitiveDesc("invoke-5", "n n n n n addr --  : invoke a 5 arg void fn", &wordInvoke5, false);
    _ = try forth.definePrimitiveDesc("invoke-6", "n n n n n n addr --  : invoke a 6 arg void fn", &wordInvoke6, false);
    _ = try forth.definePrimitiveDesc("invoke-7", "n n n n n n n addr --  : invoke a 7 arg void fn", &wordInvoke7, false);
}
