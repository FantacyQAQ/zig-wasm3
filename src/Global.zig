const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;
const Error = @import("errmap.zig").Error;
const inner = @import("inner.zig");

pub const Global = @This();

impl: c.IM3Global,

pub const Value = union(enum) {
    Int32: i32,
    Int64: i64,
    Float32: f32,
    Float64: f64,
    FuncRef: ?*anyopaque,
    ExternRef: ?*anyopaque,
    ExnRef: ?*anyopaque,
};
pub const Type = c.M3ValueType;

pub inline fn getType(this: Global) Type {
    return c.m3_GetGlobalType(this.impl);
}

pub fn get(this: Global) !Value {
    var tagged_union: c.M3TaggedValue = undefined;
    tagged_union.kind = .None;
    try ErrorMapping.mapError(c.m3_GetGlobal(this.impl, &tagged_union));
    return switch (tagged_union.kind) {
        .None => Error.GlobalTypeMismatch,
        .Unknown => Error.GlobalTypeMismatch,
        .Int32 => Value{ .Int32 = tagged_union.value.int32 },
        .Int64 => Value{ .Int64 = tagged_union.value.int64 },
        .Float32 => Value{ .Float32 = tagged_union.value.float32 },
        .Float64 => Value{ .Float64 = tagged_union.value.float64 },
        else => unreachable,
    };
}

pub fn set(this: Global, value_union: Value) !void {
    var tagged_union: c.M3TaggedValue = switch (value_union) {
        .Int32 => |value| .{ .kind = .Int32, .value = .{ .int32 = value } },
        .Int64 => |value| .{ .kind = .Int64, .value = .{ .int64 = value } },
        .Float32 => |value| .{ .kind = .Float32, .value = .{ .float32 = value } },
        .Float64 => |value| .{ .kind = .Float64, .value = .{ .float64 = value } },
        else => return Error.InvalidTypeId,
    };
    return ErrorMapping.mapError(c.m3_SetGlobal(this.impl, &tagged_union));
}
