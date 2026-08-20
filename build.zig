const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wasm3 = b.dependency("wasm3", .{ .libm3 = true });
    wasm3.artifact("m3").root_module.addCMacro("d_m3HasWASI", "1");

    const lib_mod = b.addModule("wasm3", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addCSourceFile(.{
        .file = b.path("src/wasm3_extra.c"),
    });
    lib_mod.addIncludePath(wasm3.path("source"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zig-wasm3",
        .root_module = lib_mod,
    });
    lib_mod.linkLibrary(wasm3.artifact("m3"));

    b.installArtifact(lib);

    const wasm_mod = b.addModule("wasm_example_root", .{
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi }),
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("example/wasm_src.zig"),
    });
    const wasm_build = b.addExecutable(.{
        .name = "wasm_example",
        .root_module = wasm_mod,
    });
    wasm_build.entry = .disabled;
    wasm_build.root_module.export_symbol_names = &.{
        "allocBytes",
        "printStringZ",
        "addFive",
        "main",
    };
    b.installArtifact(wasm_build);

    const exe_mod = b.addModule("zig_wasm3_test_root", .{
        .root_source_file = b.path("example/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = "zig_wasm3_test",
        .root_module = exe_mod,
    });
    exe_mod.addImport("wasm3", lib_mod);
    exe_mod.linkLibrary(lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addArtifactArg(wasm_build);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
