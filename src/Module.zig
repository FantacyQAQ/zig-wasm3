const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;
const Error = @import("errmap.zig").Error;
const inner = @import("inner.zig");
const Runtime = @import("Runtime.zig");
const Global = @import("Global.zig");

pub const Module = @This();

impl: c.IM3Module,

pub fn deinit(this: inner.Module) void {
    c.m3_FreeModule(this.impl);
}

pub fn getMemory(this: inner.Module, memory_index: u32) ?[]u8 {
    var size: usize = 0;
    const mem = c.m3_GetMemory(this.impl, &size, memory_index);
    if (mem) |valid| return valid[0..size];
    return null;
}

pub fn getMemorySize(this: inner.Module, memory_index: u32) usize {
    return c.m3_GetMemorySize(this.impl, memory_index);
}

pub fn findExportedMemory(this: inner.Module, name: [:0]const u8) !u32 {
    var idx: u32 = undefined;
    try ErrorMapping.mapError(c.m3_FindExportedMemory(this.impl, name, &idx));
    return idx;
}

pub fn bindImportMemory(this: inner.Module, import_module: [:0]const u8, memory_idx: u32) !void {
    try ErrorMapping.mapError(c.m3_BindImportMemory(this.impl, import_module, memory_idx));
}

fn mapTypeToChar(comptime T: type) u8 {
    switch (T) {
        void => return 'v',
        u32, i32 => return 'i',
        u64, i64 => return 'I',
        f32 => return 'f',
        f64 => return 'F',
        else => {},
    }
    if (comptime (inner.isSandboxPtr(T) or inner.inner.isOptSandboxPtr(T))) {
        return '*';
    }
    switch (@typeInfo(T)) {
        .pointer => |ptrti| {
            if (ptrti.size == .one) {
                @compileError("Please use a wasm3.SandboxPtr instead of raw pointers!");
            }
        },
    }
    @compileError("Invalid type " ++ @typeName(T) ++ " for WASM interop!");
}

pub fn linkWasi(this: Module) !void {
    return ErrorMapping.mapError(c.m3_LinkWASI(this.impl));
}

/// Links all functions in a struct to the module.
/// library_name: the name of the library this function should belong to.
/// library: a struct containing functions that should be added to the module.
///          See linkRawFunction(...) for information about valid function signatures.
/// userdata: A single-item pointer passed to the function as the first argument when called.
///           Not accessible from within wasm, handled by the interpreter.
///           If you don't want userdata, pass a void literal {}.
pub fn linkLibrary(this: Module, library_name: [:0]const u8, comptime library: type, userdata: anytype) !void {
    inline for (@typeInfo(library).@"struct".decls) |decl| {
        // if (decl.is_pub) {
        const fn_name_z = comptime get_name: {
            var name_buf: [decl.name.len:0]u8 = undefined;
            std.mem.copyForwards(u8, &name_buf, decl.name);
            break :get_name name_buf;
        };
        try this.linkRawFunction(library_name, &fn_name_z, @field(library, decl.name), userdata);
        // }
    }
}

/// Links a native function into the module.
/// library_name: the name of the library this function should belong to.
/// function_name: the name the function should have in module-space.
/// function: a zig function (not function pointer!).
///           Valid argument and return types are:
///             i32, u32, i64, u64, f32, f64, void, and pointers to basic types.
///           Userdata, if provided, is the first argument to the function.
/// userdata: A single-item pointer passed to the function as the first argument when called.
///           Not accessible from within wasm, handled by the interpreter.
///           If you don't want userdata, pass a void literal {}.
pub fn linkRawFunction(this: Module, library_name: [:0]const u8, function_name: [:0]const u8, comptime function: anytype, userdata: anytype) !void {
    errdefer {
        std.log.err("Failed to link proc {s}.{s}!\n", .{ library_name, function_name });
    }
    const has_userdata = @TypeOf(userdata) != void;
    comptime validate_userdata: {
        if (has_userdata) {
            switch (@typeInfo(@TypeOf(userdata))) {
                .pointer => |ptrti| {
                    if (ptrti.size == .one) {
                        break :validate_userdata;
                    }
                },
                else => {},
            }
            @compileError("Expected a single-item pointer for the userdata, got " ++ @typeName(@TypeOf(userdata)));
        }
    }
    const UserdataType = @TypeOf(userdata);
    const sig = comptime generate_signature: {
        switch (@typeInfo(@TypeOf(function))) {
            .@"fn" => |fnti| {
                const sub_data = if (has_userdata) 1 else 0;
                var arg_str: [fnti.params.len + 3 - sub_data:0]u8 = undefined;
                arg_str[0] = mapTypeToChar(fnti.return_type orelse void);
                arg_str[1] = '(';
                arg_str[arg_str.len - 1] = ')';
                for (fnti.params[sub_data..], 0..) |arg, i| {
                    if (arg.is_generic) {
                        @compileError("WASM does not support generic arguments to native functions!");
                    }
                    arg_str[2 + i] = mapTypeToChar(arg.type.?);
                }
                break :generate_signature arg_str;
            },
            else => @compileError("Expected a function, got " ++ @typeName(@TypeOf(function))),
        }
        unreachable;
    };
    const lambda = struct {
        pub fn l(_: c.IM3Runtime, import_ctx: *c.M3ImportContext, sp: [*c]u64, _mem: ?*anyopaque) callconv(.c) ?*const anyopaque {
            comptime var type_arr: []const type = &[0]type{};
            if (has_userdata) {
                type_arr = type_arr ++ @as([]const type, &[1]type{UserdataType});
            }
            std.debug.assert(_mem != null);
            const mem = @intFromPtr(_mem);
            var stack = @intFromPtr(sp);
            const stride = @sizeOf(u64) / @sizeOf(u8);

            switch (@typeInfo(@TypeOf(function))) {
                .@"fn" => |fnti| {
                    const RetT = fnti.return_type orelse void;

                    const return_pointer = comptime (inner.isSandboxPtr(RetT) or inner.isOptSandboxPtr(RetT));

                    const RetPtr = comptime if (RetT == void) void else if (return_pointer) *u32 else *RetT;
                    var ret_val: RetPtr = undefined;
                    if (RetT != void) {
                        ret_val = @ptrFromInt(stack);
                        stack += stride;
                    }

                    const sub_data = if (has_userdata) 1 else 0;
                    inline for (fnti.params[sub_data..]) |arg| {
                        if (arg.is_generic) unreachable;
                        type_arr = type_arr ++ @as([]const type, &[1]type{arg.type.?});
                    }

                    var args: std.meta.Tuple(type_arr) = undefined;

                    comptime var idx: usize = 0;
                    if (has_userdata) {
                        args[idx] = @ptrCast(@alignCast(import_ctx.userdata));
                        idx += 1;
                    }
                    inline for (fnti.params[sub_data..]) |arg| {
                        if (arg.is_generic) unreachable;

                        const ArgT = arg.type.?;

                        if (comptime (inner.isSandboxPtr(ArgT) or inner.isOptSandboxPtr(ArgT))) {
                            if (comptime (inner.isSandboxPtr(ArgT) or inner.isOptSandboxPtr(ArgT))) {
                                const vm_arg_addr: u32 = @as(*u32, @ptrFromInt(stack)).*;
                                args[idx] = inner.fromLocalPtr(ArgT, vm_arg_addr, mem);
                            } else {
                                args[idx] = @as(*ArgT, @ptrFromInt(stack)).*;
                            }
                            idx += 1;
                            stack += stride;
                        }

                        if (RetT == void) {
                            @call(.always_inline, function, args);
                        } else {
                            const returned_value = @call(.always_inline, function, args);
                            if (return_pointer) {
                                ret_val.* = inner.toLocalPtr(returned_value);
                            } else {
                                ret_val.* = returned_value;
                            }
                        }

                        return c.m3Err_none;
                    }
                },
                else => unreachable,
            }
        }
    }.l;
    try ErrorMapping.mapError(c.m3_LinkRawFunctionEx(this.impl, library_name, function_name, @as([*]const u8, &sig), lambda, if (has_userdata) userdata else null));
}

/// Optional, compiles all functions in the module
pub inline fn compile(this: inner.Module) !void {
    return ErrorMapping.mapError(c.m3_CompileModule(this.impl));
}

/// This is optional.
pub inline fn runStart(this: inner.Module) !void {
    return ErrorMapping.mapError(c.m3_RunStart(this.impl));
}

/// Don't free this, it's a member of the inner.Module.
/// Returns a generic name if the module is unnamed, such as "<unknown>"
pub inline fn getName(this: inner.Module) ![:0]const u8 {
    const name = try ErrorMapping.mapError(c.m3_GetModuleName(this.impl));
    return std.mem.span(name);
}

/// Assumes that name will last as long as the module, does not copy
pub inline fn setName(this: inner.Module, name: [:0]const u8) void {
    c.m3_SetModuleName(this.impl, name);
}

pub inline fn getRuntime(this: inner.Module) Runtime {
    return .{ .impl = c.m3_GetModuleRuntime(this.impl) };
}

pub inline fn linkGlobal(this: inner.Module, module_name: [:0]const u8, global_name: [:0]const u8) !?Global.Value {
    var raw: c.M3TaggedValue = undefined;
    try ErrorMapping.mapError(c.m3_LinkGlobal(this.impl, module_name, global_name, &raw));
    return switch (raw.kind) {
        .None => null,
        .Unknown => Error.GlobalTypeMismatch,
        .Int32 => .{ .Int32 = raw.value.int32 },
        .Int64 => .{ .Int64 = raw.value.int64 },
        .Float32 => .{ .Float32 = raw.value.float32 },
        .Float64 => .{ .Float64 = raw.value.float64 },
    };
}

pub inline fn findGlobal(this: Module, global_name: [:0]const u8) ?Global {
    if (c.m3_FindGlobal(this.impl, global_name)) |global_ptr| {
        return Global{ .impl = global_ptr };
    }
    return null;
}
