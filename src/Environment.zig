const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;
const Error = @import("errmap.zig").Error;
const inner = @import("inner.zig");
const Runtime = @import("Runtime.zig");
const Module = @import("Module.zig");

pub const Environment = @This();

impl: c.IM3Environment,

pub inline fn init() Environment {
    return .{ .impl = c.m3_NewEnvironment() };
}
pub inline fn deinit(this: Environment) void {
    c.m3_FreeEnvironment(this.impl);
}
pub inline fn setCustomSectionHandler(this: Environment, comptime handler: fn (module: Module, name: []const u8, bytes: []const u8) Error!void) void {
    const handler_adapter = struct {
        pub fn l(module: c.IM3Module, name: [*:0]const u8, start: [*]const u8, end: *const u8) callconv(.c) c.M3Result {
            const result = handler(.{ .impl = module }, std.mem.span(name), start[0..(@intFromPtr(end) - @intFromPtr(start))]);
            return ErrorMapping.mapErrorReverse(result);
        }
    }.l;
    c.m3_SetCustomSectionHandler(this.impl, handler_adapter);
}
pub inline fn createRuntime(this: Environment, stack_size: u32, userdata: ?*anyopaque) Runtime {
    return .{ .impl = c.m3_NewRuntime(this.impl, stack_size, userdata) };
}
pub inline fn parseModule(this: Environment, wasm: []const u8) !Module {
    var mod = Module{ .impl = undefined };
    const res = c.m3_ParseModule(this.impl, &mod.impl, wasm.ptr, @intCast(wasm.len));
    try ErrorMapping.mapError(res);
    return mod;
}
