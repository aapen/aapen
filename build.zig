const std = @import("std");
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

    const target = std.zig.CrossTarget{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    };

    const board = b.option(SupportedBoard, "board", "Select a target board for the kernel build") orelse .pi3;
    const options = b.addOptions();
    options.addOption(SupportedBoard, "board", board);

    const optimize = b.standardOptimizeOption(.{});
    const bin_basename = b.option([]const u8, "image", "Base name for the kernel binaries (both elf and img)") orelse "kernel8";
    const elf_name = try fmt.allocPrint(allocator, "{s}.elf", .{bin_basename});
    defer allocator.free(elf_name);
    const img_name = try fmt.allocPrint(allocator, "{s}.img", .{bin_basename});
    defer allocator.free(img_name);

    const kernel = b.addExecutable(.{
        .name = elf_name,
        .target = target,
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .link_libc = false,
    });

    //    kernel.addModule("config", configModule(b));
    kernel.addOptions("config", options);

    kernel.addIncludePath(.{ .path = "include" });
    kernel.addCSourceFile(.{ .file = .{ .path = "src/printf.c" }, .flags = &[_][]const u8{} });
    kernel.addCSourceFile(.{ .file = .{ .path = "src/disassemble.c" }, .flags = &[_][]const u8{} });
    kernel.addAssemblyFile(.{ .path = "src/arch/aarch64/exceptions.S" });
    kernel.addAssemblyFile(.{ .path = "src/arch/aarch64/mmu.S" });
    kernel.addAssemblyFile(.{ .path = "src/arch/aarch64/cache.S" });
    kernel.addAssemblyFile(.{ .path = "src/arch/aarch64/boot.S" });
    kernel.addAssemblyFile(.{ .path = "src/arch/aarch64/util.S" });
    kernel.setLinkerScriptPath(.{ .path = "src/arch/aarch64/kernel.ld" });

    b.installArtifact(kernel);

    const objcopy = b.addObjCopy(kernel.getOutputSource(), .{
        .format = std.Build.Step.ObjCopy.RawFormat.bin,
    });

    objcopy.step.dependOn(&kernel.step);

    const install_elf = b.addInstallFile(kernel.getOutputSource(), elf_name);
    b.getInstallStep().dependOn(&install_elf.step);

    const install_obj = b.addInstallFile(objcopy.getOutputSource(), img_name);
    b.getInstallStep().dependOn(&install_obj.step);
}

fn addModule(cs: *Build.CompileStep, name: []const u8, source: []const u8) void {
    const b = cs.step.owner;
    cs.addModule(name, b.addModule(name, .{ .source_file = .{ .path = source } }));
}
