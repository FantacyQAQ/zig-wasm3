const std = @import("std");

pub fn isSandboxPtr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "_is_wasm3_local_ptr"),
        else => false,
    };
}

pub fn isOptSandboxPtr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => |opt| isSandboxPtr(opt.child),
        else => false,
    };
}

pub fn fromLocalPtr(comptime T: type, localptr: u32, local_heap: usize) T {
    if (comptime isOptSandboxPtr(T)) {
        const Child = std.meta.Child(T);
        if (localptr == 0) return null;
        return Child{
            .local_heap = local_heap,
            .host_ptr = @ptrFromInt(local_heap + @as(usize, @intCast(localptr))),
        };
    } else if (comptime isSandboxPtr(T)) {
        std.debug.assert(localptr != 0);
        return T{
            .local_heap = local_heap,
            .host_ptr = @ptrFromInt(local_heap + @as(usize, @intCast(localptr))),
        };
    } else {
        @compileError("Expected a SandboxPtr or a ?SandboxPtr, got " ++ @typeName(T));
    }
}

pub fn toLocalPtr(sandbox_ptr: anytype) u32 {
    const T = @TypeOf(sandbox_ptr);
    if (comptime isOptSandboxPtr(T)) {
        if (sandbox_ptr) |np| {
            const lp = np.localPtr();
            std.debug.assert(lp != 0);
            return lp;
        } else return 0;
    } else if (comptime isSandboxPtr(T)) {
        const lp = sandbox_ptr.localPtr();
        std.debug.assert(lp != 0);
        return lp;
    } else {
        @compileError("Expected a SandboxPtr or a ?SandboxPtr");
    }
}
