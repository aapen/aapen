const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

const Module = struct {
    name: []const u8,
    source: []const u8,
};

const io = Module{ .name = "io", .source = "lib/io.zig" };

pub fn build(b: *std.Build) void {
    const target = std.zig.CrossTarget{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    };

    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel8.elf",
        .target = target,
        .root_source_file = .{ .path = "main.zig" },
        .optimize = optimize,
        .link_libc = false,
    });

    addModule(kernel, io);

    kernel.addAssemblyFile("boot.s");
    kernel.addAssemblyFile("qemu.s");
    kernel.setLinkerScriptPath(.{ .path = "kernel.ld" });

    const objcopy = b.addObjCopy(kernel.getOutputSource(), .{
        .basename = "./kernel8.img",
        .format = std.Build.Step.ObjCopy.RawFormat.bin,
    });

    objcopy.step.dependOn(&kernel.step);

    const install_elf = b.addInstallFile(kernel.getOutputSource(), "kernel8.elf");
    b.getInstallStep().dependOn(&install_elf.step);

    const install_obj = b.addInstallFile(objcopy.getOutputSource(), "kernel8.img");
    b.getInstallStep().dependOn(&install_obj.step);
}

fn addModule(cs: *Build.CompileStep, module: Module) void {
    const b = cs.step.owner;
    const name = module.name;

    // I don't understand why name has to be duplicated here.
    cs.addModule(name, b.addModule(name, .{ .source_file = .{ .path = module.source } }));
}
