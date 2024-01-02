const std = @import("std");
const log = std.log.scoped(.forty);

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const memory = @import("memory.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

pub const InteropCall = struct {
    forth: *Forth = undefined,
    header: *Header = undefined,
};

pub fn defineNamespace(comptime Module: type, comptime as: []const u8, forth: *Forth) !void {
    const decls = @typeInfo(Module).Struct.decls;

    inline for (decls) |d| {
        const t = @typeInfo(@TypeOf(@field(Module, d.name)));
        switch (t) {
            .Fn => |f| {
                if (comptime isSuitable(f)) {
                    const caller = callerFor(Module, as, d.name);
                    _ = try forth.definePrimitiveDesc(caller.name, caller.desc, &caller.invoke, false);
                }
            },

            inline else => {},
        }
    }
}

fn isSuitable(comptime f: std.builtin.Type.Fn) bool {
    if (f.is_generic or f.calling_convention != .Unspecified or f.is_var_args or f.params.len == 0) {
        return false;
    }

    var has_interop_marker = false;
    inline for (f.params) |p| {
        if (p.type == InteropCall) {
            has_interop_marker = true;
        }
    }
    if (!has_interop_marker) {
        return false;
    }

    if (!acceptableReturnType(f.return_type.?)) {
        return false;
    }
    return true;
}

pub fn callerFor(comptime T: type, comptime module_alias: []const u8, comptime fn_name: []const u8) type {
    const decl = @field(T, fn_name);
    const decl_type = @TypeOf(decl);
    const decl_info = @typeInfo(decl_type);

    switch (decl_info) {
        .Fn => |f| {
            return struct {
                const name: []const u8 = module_alias ++ fn_name;
                const desc: []const u8 = "description coming soon";

                pub fn invoke(forth: *Forth, header: *Header) ForthError!void {
                    const interop: InteropCall = .{
                        .forth = forth,
                        .header = header,
                    };

                    const params = try packParameters(interop, f);
                    const retval = @call(.auto, decl, params);
                    try unpackReturnValue(forth, retval);
                }
            };
        },
        else => {
            @compileError(fn_name ++ " is a " ++ @typeName(decl_type) ++ " not a function");
        },
    }
}

fn ParameterTuple(comptime f: std.builtin.Type.Fn) type {
    var tuple_fields: [f.params.len]std.builtin.Type.StructField = undefined;
    inline for (f.params, 0..) |p, i| {
        const T = @TypeOf(p);
        tuple_fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = f.params[i].type.?,
            .default_value = null,
            .is_comptime = false,
            .alignment = if (@sizeOf(T) > 0) @alignOf(T) else 0,
        };
    }
    return @Type(.{ .Struct = .{
        .is_tuple = true,
        .layout = .Auto,
        .decls = &.{},
        .fields = &tuple_fields,
    } });
}

fn packParameters(interop: InteropCall, comptime f: std.builtin.Type.Fn) !ParameterTuple(f) {
    const PT = ParameterTuple(f);
    var packed_params: PT = undefined;

    inline for (f.params, 0..) |p, i| {
        if (p.type == InteropCall) {
            packed_params[i] = interop;
        } else {
            const raw_argument = try interop.forth.stack.pop();

            const T = p.type.?;
            try coerceParameter(PT, &packed_params, i, T, raw_argument);
        }
    }

    return packed_params;
}

fn coerceParameter(comptime PT: type, into: *PT, comptime field_num: usize, comptime T: type, val: u64) !void {
    switch (@typeInfo(T)) {
        .Optional => |o| return try coerceParameter(PT, into, field_num, o.child, val),
        .Int => |i| {
            if (i.bits < 64) {
                if (i.signedness == .signed) {
                    return ForthError.Unsupported;
                } else {
                    into[field_num] = @truncate(val & std.math.maxInt(T));
                }
            } else {
                into[field_num] = @bitCast(val);
            }
        },
        .Pointer => {
            into[field_num] = @ptrFromInt(val);
        },
        .Enum => {
            into[field_num] = @enumFromInt(val);
        },
        else => |x| {
            std.debug.print("Unsupported {any}\n", .{x});
            return ForthError.Unsupported;
        },
    }
}

fn acceptableReturnType(comptime rt: type) bool {
    return switch (@typeInfo(rt)) {
        .Optional => |o| acceptableReturnType(o.child),
        .ErrorUnion => |eu| acceptableReturnType(eu.payload),
        .Void => true,
        .Int => true,
        .Pointer => true,
        .Enum => true,
        inline else => false,
    };
}

fn unpackReturnValue(forth: *Forth, retval: anytype) !void {
    switch (@typeInfo(@TypeOf(retval))) {
        .ErrorUnion => |_| {
            if (retval) |payload| {
                // no error, push zero (for the error position) then
                // the actual return value.
                try forth.stack.push(0);
                try unpackReturnValue(forth, payload);
            } else |err| {
                try forth.stack.push(@intFromError(err));
                try forth.stack.push(0x7fffffffffffffff);
            }
        },
        .Optional => |o| {
            _ = o;
            if (retval) |payload| {
                try unpackReturnValue(forth, payload);
            } else {
                try forth.stack.push(0);
            }
        },
        .Pointer => |p| {
            const converted = switch (p.size) {
                .Slice => @intFromPtr(retval.ptr),
                else => @intFromPtr(retval),
            };
            try forth.stack.push(converted);
        },
        .Void => |_| {
            // do nothing with nothing
        },
        .Int => |i| {
            if (i.bits < 64 and i.signedness == .signed) {
                // sign extend to 64 bits
                const extended: i64 = retval;
                try forth.stack.push(@bitCast(extended));
            } else {
                // simple intCast suffices
                try forth.stack.push(@intCast(retval));
            }
        },
        .Enum => {
            try forth.stack.push(@intFromEnum(retval));
        },
        inline else => |t| {
            std.debug.print("Don't know how to handle a {any}\n", .{t});
        },
    }
}
