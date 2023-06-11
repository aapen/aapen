const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.Build) void {
    const target = std.zig.CrossTarget{
        .cpu_arch = Target.Cpu.Arch.aarch64,
        .os_tag = Target.Os.Tag.freestanding,
        .abi = Target.Abi.none,
    };

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "kernel8.elf",
        .target = target,
        .root_source_file = .{ .path = "io.zig" },
        .optimize = optimize,
        .link_libc = false,
    });
    exe.addAssemblyFile("boot.s");
    exe.addAssemblyFile("qemu.s");
    exe.setLinkerScriptPath(.{ .path = "kernel.ld" });

    const objcopy = b.addObjCopy(exe.getOutputSource(), .{
        .basename = "./kernel8.img",
        .format = std.Build.Step.ObjCopy.RawFormat.bin,
    });

    objcopy.step.dependOn(&exe.step);

    const install_elf = b.addInstallFile(exe.getOutputSource(), "kernel8.elf");
    b.getInstallStep().dependOn(&install_elf.step);

    const install_obj = b.addInstallFile(objcopy.getOutputSource(), "kernel8.img");
    b.getInstallStep().dependOn(&install_obj.step);
}
