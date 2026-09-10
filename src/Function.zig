const std = @import("std");

const c = @import("c.zig");
const root = @import("root.zig");
const inner = @import("inner.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;
const Module = @import("Module.zig");

pub const Function = @This();

impl: c.IM3Function,

pub inline fn getArgCount(this: Function) u32 {
    return c.m3_GetArgCount(this.impl);
}
pub inline fn getRetCount(this: Function) u32 {
    return c.m3_GetRetCount(this.impl);
}
pub inline fn getArgType(this: Function, idx: u32) c.M3ValueType {
    return c.m3_GetArgType(this.impl, idx);
}
pub inline fn getRetType(this: Function, idx: u32) c.M3ValueType {
    return c.m3_GetRetType(this.impl, idx);
}
/// Call a function, using a provided tuple for arguments.
/// TYPES ARE NOT VALIDATED. Be careful
/// TDOO: Test this! Zig has weird symbol export issues with wasm right now,
///       so I can't verify that arguments or return values are properly passes!
pub inline fn call(this: Function, comptime RetType: type, args: anytype) !RetType {
    if (this.getRetCount() > 1) {
        return error.TooManyReturnValues;
    }

    const ArgsType = @TypeOf(args);
    if (@typeInfo(ArgsType) != .@"struct") {
        @compileError("Expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }
    const fields_info = std.meta.fields(ArgsType);

    const count = fields_info.len;
    comptime var ptr_i: comptime_int = 0;
    const num_pointers = comptime ptr_count: {
        var num_ptrs: comptime_int = 0;
        var i: comptime_int = 0;
        while (i < count) : (i += 1) {
            const ArgType = @TypeOf(args[i]);
            if (inner.isSandboxPtr(ArgType) or inner.isOptSandboxPtr(ArgType)) {
                num_ptrs += 1;
            }
        }
        break :ptr_count num_ptrs;
    };
    var pointer_values: [num_pointers]u32 = undefined;

    var arg_arr: [count]?*const anyopaque = undefined;
    inline for (args, 0..) |arg, i| {
        const ArgType = @TypeOf(arg);
        if (comptime (inner.isSandboxPtr(ArgType) or inner.isOptSandboxPtr(ArgType))) {
            if (pointer_values.len > 0) {
                pointer_values[ptr_i] = inner.toLocalPtr(arg);
                arg_arr[i] = @ptrCast(&pointer_values[ptr_i]);
                ptr_i += 1;
            } else {
                unreachable;
            }
        } else {
            arg_arr[i] = @ptrCast(&arg);
        }
    }
    try ErrorMapping.mapError(c.m3_Call(this.impl, @intCast(count), if (count == 0) null else &arg_arr));

    if (RetType == void) return;

    const Extensions = struct {
        pub extern fn wasm3_addon_get_fn_mem_ptr(func: c.IM3Function) [*c]u8;
    };

    var return_data_buffer: u64 = undefined;
    const return_ptr: *anyopaque = @ptrCast(&return_data_buffer);
    try ErrorMapping.mapError(c.m3_GetResults(this.impl, 1, &[1]?*anyopaque{return_ptr}));

    if (comptime (inner.isSandboxPtr(RetType) or inner.isOptSandboxPtr(RetType))) {
        const mem_ptr = Extensions.wasm3_addon_get_fn_mem_ptr(this.impl);
        return inner.fromLocalPtr(
            RetType,
            @as(*u32, @ptrCast(@alignCast(return_ptr))).*,
            @intFromPtr(mem_ptr),
        );
    } else {
        switch (RetType) {
            i8, i16, i32, i64, u8, u16, u32, u64, f32, f64 => {
                return @as(*RetType, @ptrCast(@alignCast(return_ptr))).*;
            },
            else => {
                @compileLog("Erroring anyway, is this wrong?", inner.isSandboxPtr(RetType) or inner.isOptSandboxPtr(RetType));
                @compileError("Invalid WebAssembly return type " ++ @typeName(RetType) ++ "!");
            },
        }
    }
}

/// Don't free this, it's a member of the Function.
/// Returns a generic name if the module is unnamed, such as "<unnamed>"
pub inline fn getName(this: Function) ![:0]const u8 {
    const name = try ErrorMapping.mapError(c.m3_GetFunctionName(this.impl));
    return std.mem.span(name);
}

pub inline fn getModule(this: Function) inner.Module {
    return .{ .impl = c.m3_GetFunctionModule(this.impl) };
}
