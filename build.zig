const std = @import("std");
const Allocator = std.mem.Allocator;
const fmt = std.fmt;

const Build = std.Build;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const Module = std.Build.Module;

const SupportedBoard = enum {
    pi3,
    pi4,
    pi400,
    pi5,
};

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const target = b.resolveTargetQuery(.{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    });

    const testname = b.option([]const u8, "testname", "Name of the in-kernel test to build and run") orelse "";

    const board = b.option(SupportedBoard, "board", "Select a target board for the kernel build") orelse .pi3;
    const options = b.addOptions();
    options.addOption(SupportedBoard, "board", board);
    options.addOption([]const u8, "testname", testname);

    const optimize = b.standardOptimizeOption(.{});
    const bin_basename = b.option([]const u8, "image", "Base name for the kernel binaries (both elf and img)") orelse "kernel8";

    const elf_name = try fmt.allocPrint(allocator, "{s}.elf", .{bin_basename});
    defer allocator.free(elf_name);

    const img_name = try fmt.allocPrint(allocator, "{s}.img", .{bin_basename});
    defer allocator.free(img_name);

    const compile_kernel = b.addExecutable(.{
        .name = elf_name,
        .target = target,
        .root_source_file = b.path("./src/main.zig"),
        .optimize = optimize,
        .link_libc = false,
    });

    compile_kernel.root_module.addOptions("config", options);
    compile_kernel.addCSourceFile(.{ .file = b.path("src/printf.c"), .flags = &[_][]const u8{} });
    compile_kernel.addCSourceFile(.{ .file = b.path("src/disassemble.c"), .flags = &[_][]const u8{} });
    compile_kernel.addIncludePath(b.path("include"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/armforth.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/atomic.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/boot.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/context_switch.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/exceptions.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/mmu.S"));
    compile_kernel.addAssemblyFile(b.path("src/arch/aarch64/util.S"));
    compile_kernel.setLinkerScriptPath(b.path("src/arch/aarch64/kernel.ld"));

    b.installArtifact(compile_kernel);

    const extract_image = b.addObjCopy(compile_kernel.getEmittedBin(), .{
        .format = std.Build.Step.ObjCopy.RawFormat.bin,
    });

    extract_image.step.dependOn(&compile_kernel.step);

    const install_elf = b.addInstallFile(compile_kernel.getEmittedBin(), elf_name);
    b.getInstallStep().dependOn(&install_elf.step);

    const install_image = b.addInstallFile(extract_image.getOutputSource(), img_name);

    if (!isTestBuild(testname)) {
        const build_symbols = buildSymbolTable(b, compile_kernel, extract_image);
        b.getInstallStep().dependOn(&build_symbols.step);
        install_image.step.dependOn(&build_symbols.step);
    }

    b.getInstallStep().dependOn(&install_image.step);
}

fn buildSymbolTable(b: *std.Build, compile_kernel: *std.Build.Step.Compile, extract_image: *std.Build.Step.ObjCopy) *std.Build.Step.Run {
    const tool = b.addExecutable(.{
        .target = b.host,
        .name = "build-symbtab",
        .root_source_file = b.path("tools/build-symtab/src/main.zig"),
    });

    const run_tool = b.addRunArtifact(tool);
    run_tool.addFileArg(compile_kernel.getEmittedBin());
    run_tool.addFileArg(extract_image.getOutput());
    return run_tool;
}

fn isTestBuild(testname: []const u8) bool {
    return testname.len > 0;
}
