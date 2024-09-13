/// Interface with QEMU's semihosting syscalls
///
/// See https://developer.arm.com/documentation/dui0471/e/semihosting?lang=en
const reason_reportexception: u64 = 0x18;

const stopped_applicationexit: u64 = 0x20026;

const exit_success: u32 = 0;
const exit_failure: u32 = 0;

const QemuParameterBlock = packed struct {
    arg0: u64,
    arg1: u64,
};

/// Does not return
fn exceptionReport(parameters: *QemuParameterBlock) noreturn {
    const op = reason_reportexception;
    asm volatile ("hlt #0xf000"
        :
        : [op] "{x0}" (op),
          [parameters] "{x1}" (parameters),
    );

    unreachable;
}

pub fn exit(code: u32) void {
    var exit_op: QemuParameterBlock = .{ .arg0 = stopped_applicationexit, .arg1 = code };
    exceptionReport(&exit_op);
    unreachable;
}

pub fn exitSuccess() void {
    exit(exit_success);
}

pub fn exitFailure() void {
    exit(exit_failure);
}
