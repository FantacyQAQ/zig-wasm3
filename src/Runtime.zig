const std = @import("std");

const c = @import("c.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;
const Module = @import("Module.zig");
const Function = @import("Function.zig");

pub const Runtime = @This();

impl: c.IM3Runtime,

pub inline fn deinit(this: Runtime) void {
    c.m3_FreeRuntime(this.impl);
}

pub inline fn getUserData(this: Runtime) ?*anyopaque {
    return c.m3_GetUserData(this.impl);
}

pub inline fn loadModule(this: Runtime, module: Module) !void {
    try ErrorMapping.mapError(c.m3_LoadModule(this.impl, module.impl));
}

pub inline fn findFunction(this: Runtime, function_name: [:0]const u8) !Function {
    var func: Function = .{ .impl = undefined };
    try ErrorMapping.mapError(c.m3_FindFunction(&func.impl, this.impl, function_name.ptr));
    return func;
}
pub inline fn printRuntimeInfo(this: Runtime) void {
    c.m3_PrintRuntimeInfo(this.impl);
}

pub const ErrorInfo = c.M3ErrorInfo;
pub inline fn getErrorInfo(this: Runtime) ErrorInfo {
    var info: ErrorInfo = undefined;
    c.m3_GetErrorInfo(this.impl, &info);
    return info;
}

inline fn span(strz: ?[*:0]const u8) []const u8 {
    if (strz) |s| return std.mem.span(s);
    return "nullptr";
}

pub inline fn printError(this: Runtime) void {
    const info = this.getErrorInfo();
    this.resetErrorInfo();
    std.log.err("Wasm3 error: {s} @ {s}:{d}\n", .{ span(info.message), span(info.file), info.line });
}

pub inline fn resetErrorInfo(this: Runtime) void {
    c.m3_ResetErrorInfo(this.impl);
}

pub inline fn setValidation(this: Runtime, enable: bool) void {
    c.m3_SetValidation(this.impl, enable);
}

pub inline fn setGasLimit(this: Runtime, gas: f64) void {
    c.m3_SetGasLimit(this.impl, gas);
}

pub inline fn getGasLimit(this: Runtime) f64 {
    return c.m3_GetGasLimit(this.impl);
}

pub inline fn findModule(this: Runtime, module_name: [:0]const u8) ?Module {
    const impl = c.m3_FindModule(this.impl, module_name);
    if (impl) |valid| {
        return .{ .impl = valid };
    } else return null;
}
