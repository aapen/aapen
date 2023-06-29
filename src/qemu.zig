/// Interface with QEMU's "semihosting" syscalls
///
/// See https://developer.arm.com/documentation/dui0471/e/semihosting?lang=en
const SWI_REASON_REPORTEXCEPTION: u64 = 0x18;

const ADP_STOPPED_APPLICATIONEXIT: u64 = 0x20026;

const EXIT_SUCCESS: u32 = 0;
const EXIT_FAILURE: u32 = 0;

const QEMUParameterBlock = packed struct {
    arg0: u64,
    arg1: u64,
};

/// Does not return
fn swi_report_exception(parameters: *QEMUParameterBlock) void {
    const op = SWI_REASON_REPORTEXCEPTION;
    asm volatile ("hlt #0xf000"
        :
        : [op] "{x0}" (op),
          [parameters] "{x1}" (parameters),
    );

    unreachable;
}

pub fn exit(code: u32) void {
    var exit_op: QEMUParameterBlock = .{ .arg0 = ADP_STOPPED_APPLICATIONEXIT, .arg1 = code };
    swi_report_exception(&exit_op);
    unreachable;
}

pub fn exit_success() void {
    exit(EXIT_SUCCESS);
}

pub fn exit_failure() void {
    exit(EXIT_FAILURE);
}
