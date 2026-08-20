const std = @import("std");
const wasm3 = @import("wasm3");

const kib = 1024;
const mib = 1024 * kib;
const gib = 1024 * mib;

pub fn main(init: std.process.Init) !void {
    var gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        std.log.err("Please provide a wasm file on the command line!\n", .{});
        return error.NoArgs;
    }

    std.log.info("Loading wasm file {s}!\n", .{args[1]});

    var env = wasm3.Environment.init();
    defer env.deinit();

    var rt = env.createRuntime(16 * kib, null);
    defer rt.deinit();
    errdefer rt.printError();

    const mod_bytes = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .limited(512 * kib));
    defer gpa.free(mod_bytes);
    var mod = try env.parseModule(mod_bytes);
    try rt.loadModule(mod);
    try mod.linkWasi();

    try mod.linkLibrary("native_helpers", struct {
        pub inline fn add(_: *std.mem.Allocator, lh: i32, rh: i32, mul: wasm3.SandboxPtr(i32)) i32 {
            mul.write(lh * rh);
            return lh + rh;
        }
    }, &gpa);

    var start_fn = try rt.findFunction("main");
    start_fn.call(void, .{}) catch |e| switch (e) {
        error.TrapExit => {},
        else => return e,
    };

    var add_five_fn = try rt.findFunction("addFive");
    const num: i32 = 7;
    std.debug.print("Adding 5 to {d}: got {d}!\n", .{ num, try add_five_fn.call(i32, .{num}) });

    var alloc_fn = try rt.findFunction("allocBytes");
    var print_fn = try rt.findFunction("printStringZ");

    const my_string = "Hello, world!";

    var buffer_np = try alloc_fn.call(wasm3.SandboxPtr(u8), .{@as(u32, my_string.len + 1)});
    var buffer = buffer_np.slice(my_string.len + 1);

    std.debug.print("Allocated buffer!\n{any}\n", .{buffer});

    @memcpy(buffer[0..my_string.len], my_string);
    buffer[my_string.len] = 0;

    try print_fn.call(void, .{buffer_np});

    const optionally_null_np: ?wasm3.SandboxPtr(u8) = null;
    try print_fn.call(void, .{optionally_null_np});

    try test_globals(init);
}

/// This is in a separate file because I can't find any
/// compiler toolchains that actually work with Wasm globals yet (lol)
/// so we just ship a binary wasm file that works with them
pub fn test_globals(init: std.process.Init) !void {
    var env = wasm3.Environment.init();
    defer env.deinit();

    var rt = env.createRuntime(1 * kib, null);
    defer rt.deinit();
    errdefer rt.printError();

    const mod_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, "example/global.wasm", init.gpa, .limited(512 * kib));
    defer init.gpa.free(mod_bytes);
    var mod = try env.parseModule(mod_bytes);
    try rt.loadModule(mod);

    var one = mod.findGlobal("one") orelse {
        std.debug.panic("Failed to find global \"one\"\n", .{});
    };
    var some = mod.findGlobal("some") orelse {
        std.debug.panic("Failed to find global \"some\"\n", .{});
    };

    std.debug.print("'one' value: {d}\n", .{(try one.get()).Float32});
    std.debug.print("'some' value: {d}\n", .{(try some.get()).Float32});

    std.debug.print("Trying to set 'one' value to 5.0, should fail.\n", .{});

    one.set(.{ .Float32 = 5.0 }) catch |err| switch (err) {
        wasm3.Error.SettingImmutableGlobal => {
            std.debug.print("Failed successfully!\n", .{});
        },
        else => {
            std.debug.print("Unexpected error {any}\n", .{err});
        },
    };
    std.debug.print("'one' value: {d}\n", .{(try one.get()).Float32});
    if ((try one.get()).Float32 != 1.0) {
        std.log.err("Global 'one' has a different value. This is probably a wasm3 bug!\n", .{});
    }

    var some_setter = try rt.findFunction("set_some");
    try some_setter.call(void, .{@as(f32, 25.0)});
    std.debug.print("'some' value: {d}\n", .{(try some.get()).Float32});
}
