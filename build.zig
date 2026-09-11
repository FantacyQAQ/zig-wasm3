const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const BuildWasiOptions = enum { none, simple, metawasi, uvwasi };
    const build_wasi: BuildWasiOptions = b.option(BuildWasiOptions, "build_wasi", "How to enable wasi") orelse default: {
        if (target.result.cpu.arch.isWasm() and
            target.result.os.tag == .wasi) break :default .metawasi;
        if (target.result.os.tag != .freestanding) break :default .simple;
        break :default .none;
    };
    if (build_wasi == .metawasi) {
        if (!target.result.cpu.arch.isWasm() or
            target.result.os.tag != .wasi) @panic("MetaWASI is only supported on WASI target");
    }
    const is_freestanding = target.result.os.tag == .freestanding;

    const wasm3 = b.dependency("wasm3", .{
        .target = target,
        .optimize = optimize,
        .libm3 = true,
        .build_wasi = build_wasi,
    });
    const m3 = wasm3.artifact("m3");

    const lib_mod = b.addModule("wasm3", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !is_freestanding,
    });

    if (is_freestanding) {
        m3.root_module.addCMacro("d_m3VerboseErrorMessage", "0");
        m3.root_module.addIncludePath(b.path("src/stub"));
        m3.root_module.link_libc = false;
        lib_mod.addCMacro("d_m3VerboseErrorMessage", "0");
        lib_mod.addIncludePath(b.path("src/stub"));
        lib_mod.link_libc = false;

        // Drop libm for freestanding targets.
        loop: for (m3.root_module.link_objects.items, 0..) |item, i| {
            switch (item) {
                .system_lib => |system_lib| {
                    if (std.mem.eql(u8, system_lib.name, "m")) {
                        _ = m3.root_module.link_objects.orderedRemove(i);
                        break :loop;
                    }
                },
                else => {},
            }
        }
    }

    lib_mod.addCSourceFile(.{
        .file = b.path("src/wasm3_extra.c"),
    });
    lib_mod.addIncludePath(wasm3.path("source"));

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "zig-wasm3",
        .root_module = lib_mod,
    });
    lib_mod.linkLibrary(m3);

    const lib_check = b.addLibrary(.{
        .linkage = .static,
        .name = "zig-wasm3",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const check_step = b.step("check", "check the build.");
    check_step.dependOn(&lib_check.step);

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

    if (build_wasi != .none) {
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
}
