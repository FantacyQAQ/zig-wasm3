const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const inner = @import("inner.zig");
const ErrorMapping = @import("errmap.zig").ErrorMapping;

pub const Error = @import("errmap.zig").Error;
pub const Runtime = @import("Runtime.zig");
pub const Function = @import("Function.zig");
pub const Module = @import("Module.zig");
pub const Global = @import("Global.zig");
pub const Environment = @import("Environment.zig");

pub inline fn getMemorySizeAt(mem: ?*const anyopaque) usize {
    return c.m3_GetMemorySizeAt(mem);
}

pub fn SandboxPtr(comptime T: type) type {
    comptime {
        switch (T) {
            i8, i16, i32, i64 => {},
            u8, u16, u32, u64 => {},
            else => @compileError("Invalid type for a SandboxPtr. Must be an integer!"),
        }
    }
    return struct {
        pub const _is_wasm3_local_ptr = true;
        pub const Base = T;
        local_heap: usize,
        host_ptr: *T,
        const Self = @This();

        pub inline fn localPtr(this: Self) u32 {
            return @intCast(@intFromPtr(this.host_ptr) - this.local_heap);
        }
        pub inline fn write(this: Self, val: T) void {
            std.mem.writeInt(T, std.mem.asBytes(this.host_ptr), val, .little);
        }
        pub inline fn read(this: Self) T {
            return std.mem.readInt(T, std.mem.asBytes(this.host_ptr), .little);
        }
        inline fn offsetBy(this: Self, offset: i64) *T {
            return @ptrFromInt(get_ptr: {
                if (offset > 0) {
                    break :get_ptr @intFromPtr(this.host_ptr) + @as(usize, @intCast(offset));
                } else {
                    break :get_ptr @intFromPtr(this.host_ptr) - @as(usize, @intCast(-offset));
                }
            });
        }
        /// Offset is in bytes, NOT SAFETY CHECKED.
        pub inline fn writeOffset(this: Self, offset: i64, val: T) void {
            std.mem.writeIntLittle(T, std.mem.asBytes(this.offsetBy(offset)), val);
        }
        /// Offset is in bytes, NOT SAFETY CHECKED.
        pub inline fn readOffset(this: Self, offset: i64) T {
            std.mem.readIntLittle(T, std.mem.asBytes(this.offsetBy(offset)));
        }
        // pub usingnamespace if (T == u8)
        //     struct {
        //         /// NOT SAFETY CHECKED.
        //         pub fn slice(this: Self, len: u32) callconv(.@"inline") []T {
        //             return @as([*]u8, @ptrCast(this.host_ptr))[0..@intCast(len)];
        //         }
        //     }
        // else
        //     struct {};
        /// NOT SAFETY CHECKED.
        pub inline fn slice(this: Self, len: u32) []T {
            return @as([*]u8, @ptrCast(this.host_ptr))[0..@intCast(len)];
        }
    };
}

pub inline fn yield() !void {
    return ErrorMapping.mapError(c.m3_Yield());
}
pub inline fn printM3Info() void {
    c.m3_PrintM3Info();
}
pub inline fn printProfilerInfo() void {
    c.m3_PrintProfilerInfo();
}

// HACK: Even though we're linking with libc, there's some disconnect between what wasm3 wants to link to
//       and what the platform's libc provides.
//       These functions stll exist, but for various reason, the C code in wasm3 expects functions with
//       different symbol names than the ones the system provides.
//       This isn't wasm3's fault, but I don't really know *where* blame lies, so we'll just work around it.
//       We can just reexport these functions. It's a bit hacky, but it gets things running.
// pub usingnamespace if (builtin.target.abi.isGnu() and builtin.target.os.tag != .windows)
//     struct {
//         export fn getrandom(buf: [*c]u8, len: usize, _: c_uint) i64 {
//             std.posix.getrandom(buf[0..len]) catch return 0;
//             return @intCast(len);
//         }
//     }
// else
//     struct {};
