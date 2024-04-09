const std = @import("std");

const errors = @import("errors.zig");
const ForthError = errors.ForthError;

const memory = @import("memory.zig");

const forth_module = @import("forth.zig");
const Forth = forth_module.Forth;

const memory_module = @import("memory.zig");
const Header = memory_module.Header;

pub fn defineNamespace(comptime Module: type, exports: anytype, forth: *Forth) !void {
    const exports_type_info = @typeInfo(@TypeOf(exports));
    if (exports_type_info != .Struct) @compileError("exports must be a tuple of tuples");

    inline for (exports, 0..) |exp, i| {
        const export_type = @TypeOf(exp);
        const export_type_info = @typeInfo(export_type);
        if (export_type_info != .Struct) @compileError("item " ++ i ++ " should be a tuple like { 'decl' (, 'export-as') }");

        const decl = exp[0];
        const export_as = if (export_type_info.Struct.fields.len > 1) exp[1] else decl;
        const docstring = if (export_type_info.Struct.fields.len > 2) exp[2] else "";

        if (comptime (!@hasDecl(Module, decl))) {
            @compileError("Module " ++ @typeName(Module) ++ " does not have a public declaration " ++ decl);
        }

        const t = @typeInfo(@TypeOf(@field(Module, decl)));

        switch (comptime isSuitable(t)) {
            .OK => {
                const caller = callerFor(Module, decl);
                const desc = comptime try stackEffectString(Module, decl, docstring);
                _ = try forth.definePrimitiveDesc(export_as, desc, &caller.invoke, false);
            },
            inline else => |reason| @compileError(decl ++ " is not suitable for an interop call because " ++ @tagName(reason)),
        }
    }
}

const Suitability = enum {
    OK,
    NotFunction,
    Generic,
    CallingConvention,
    VarArgs,
    CantHandleReturnType,
};

fn isSuitable(comptime t: std.builtin.Type) Suitability {
    switch (t) {
        .Fn => |f| {
            if (f.is_generic) return .Generic;
            if (f.calling_convention != .Unspecified and f.calling_convention != .Inline) return .CallingConvention;
            if (f.is_var_args) return .VarArgs;
            if (!acceptableReturnType(f.return_type.?)) return .CantHandleReturnType;
            return .OK;
        },
        inline else => return .NotFunction,
    }
}

pub fn callerFor(comptime T: type, comptime fn_name: []const u8) type {
    const decl = @field(T, fn_name);
    const decl_type = @TypeOf(decl);
    const decl_info = @typeInfo(decl_type);

    switch (decl_info) {
        .Fn => |f| {
            return struct {
                pub fn invoke(forth: *Forth, _: *Header) ForthError!void {
                    const params = try packParameters(forth, f);
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

fn stackEffectString(comptime T: type, comptime fn_name: []const u8, comptime docstring: []const u8) ![]const u8 {
    const decl_type = @TypeOf(@field(T, fn_name));
    const decl_info = @typeInfo(decl_type);

    switch (decl_info) {
        .Fn => |f| {
            return try stackEffectParameterString(f) ++ " -- " ++ try stackEffectReturnValueString(f.return_type.?) ++ " : " ++ docstring;
        },
        else => {
            @compileError(fn_name ++ " is a " ++ @typeName(decl_type) ++ " not a function");
        },
    }
}

fn stackEffectParameterString(comptime f: std.builtin.Type.Fn) ![]const u8 {
    var sigs: []const u8 = "";

    inline for (f.params) |p| {
        sigs = try parameterSigil(p.type.?) ++ " " ++ sigs;
    }

    return sigs;
}

fn parameterSigil(comptime T: type) ![]const u8 {
    switch (@typeInfo(T)) {
        .Optional => |o| return parameterSigil(o.child),
        .Int, .Enum, .Bool => return "n",
        .Pointer => return "a",
        else => @compileError("Unsupported parameter type " ++ @typeName(T)),
    }
}

fn stackEffectReturnValueString(comptime T: type) ![]const u8 {
    switch (@typeInfo(T)) {
        .ErrorUnion => |eu| {
            return "e " ++ try stackEffectReturnValueString(eu.payload);
        },
        .Optional => |o| {
            return stackEffectReturnValueString(o.child);
        },
        .Pointer => {
            return "a";
        },
        .Int, .Enum, .Bool => {
            return "n";
        },
        .Void => {
            return "";
        },
        else => {
            @compileError("Unsupported return value type " ++ @typeName(T));
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

fn packParameters(forth: *Forth, comptime f: std.builtin.Type.Fn) !ParameterTuple(f) {
    const PT = ParameterTuple(f);
    var packed_params: PT = undefined;

    inline for (f.params, 0..) |p, i| {
        const raw_argument = try forth.stack.pop();

        const T = p.type.?;
        try coerceParameter(PT, &packed_params, i, T, raw_argument);
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
        .Bool => {
            into[field_num] = if (val != 0) true else false;
        },
        .Pointer => {
            into[field_num] = @ptrFromInt(val);
        },
        .Enum => {
            into[field_num] = @enumFromInt(val);
        },
        else => {
            @compileError("Unsupported parameter type " ++ @typeName(T));
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
        .Bool => true,
        inline else => false,
    };
}

fn unpackReturnValue(forth: *Forth, retval: anytype) !void {
    switch (@typeInfo(@TypeOf(retval))) {
        .ErrorUnion => |eu| {
            if (retval) |payload| {
                // no error, push zero (for the error position) then
                // the actual return value.
                try forth.stack.push(0);
                try unpackReturnValue(forth, payload);
            } else |err| {
                try forth.stack.push(@intFromError(err));
                if (@typeInfo(eu.payload) != std.builtin.Type.Void) {
                    try forth.stack.push(0x7fff_ffff_ffff_ffff); // bitpattern for -1 as u64
                }
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
        .Bool => {
            const b: u64 = if (retval) 1 else 0;
            try forth.stack.push(b);
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
