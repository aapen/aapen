const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

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
        .root_source_file = .{ .path = "src/main.zig" },
        .optimize = optimize,
        .link_libc = false,
    });

    kernel.addIncludePath("include");
    kernel.addAssemblyFile("src/arch/aarch64/exceptions.S");
    kernel.addAssemblyFile("src/arch/aarch64/mmu.S");
    kernel.addAssemblyFile("src/arch/aarch64/cache.S");
    kernel.addAssemblyFile("src/arch/aarch64/boot.S");
    kernel.addAssemblyFile("src/arch/aarch64/util.S");
    kernel.setLinkerScriptPath(.{ .path = "src/arch/aarch64/kernel.ld" });

    b.installArtifact(kernel);

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

fn addModule(cs: *Build.CompileStep, name: []const u8, source: []const u8) void {
    const b = cs.step.owner;
    cs.addModule(name, b.addModule(name, .{ .source_file = .{ .path = source } }));
}
