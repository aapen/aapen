const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const printf = root.printf;
const kernelMessage = root.debug.kernelMessage;

const time = @import("../time.zig");
const GPIO = @import("bcm_gpio.zig");
const bcm_peripheral_clocks = @import("../drivers/bcm_peripheral_clocks.zig");

const Forth = @import("../forty/forth.zig").Forth;
const PeripheralClockController = bcm_peripheral_clocks.PeripheralClockController;
const CLOCK_EMMC = bcm_peripheral_clocks.CLOCK_EMMC;
const InterruptController = root.HAL.InterruptController;
const IrqHandler = InterruptController.IrqHandler;
const IrqId = InterruptController.IrqId;
extern fn spinDelay(cpu_cycles: u32) void;

const Self = @This();

const ScrRegister = extern struct {
    scr: [2]u32,
    bus_widths: u32,
    version: u32,
};

const Device = struct {
    last_success: bool = false,
    transfer_blocks: u32 = 0,
    last_command: Cmd = undefined,
    last_command_value: u32 = 0,
    block_size: u32 = 0,
    last_response: [4]u32 = undefined,
    sdhc: bool = false,
    ocr: u16 = 0,
    rca: u32 = 0,
    offset: u64 = 0,
    buffer: [*]u32 = undefined,
    base_clock: u32 = 0,
    last_error: u32 = 0,
    last_interrupt: u32 = 0,
    scr: ScrRegister = undefined,
};

const RespType = struct {
    const RTInvalid: u32 = 0xface;

    const RTNone: u32 = 0;
    const RT136: u32 = 1;
    const RT48: u32 = 2;
    const RT48Busy: u32 = 3;
};

// TODO should some of these be bools?

const Cmd = struct {
    resp_a: u1,
    block_count: u1,
    auto_command: u2,
    direction: u1,
    multiblock: u1,
    resp_b: u10,
    response_type: u2,
    res0: u1,
    crc_enable: u1,
    idx_enable: u1,
    is_data: u1,
    cmd_type: u2,
    index: u6,

    code: u32,

    pub fn init(ra: u1, bc: u1, ac: u2, dir: u1, mb: u1, rb: u10, rt: u2, r0: u1, ce: u1, ie: u1, isd: u1, ct: u2, idx: u6) Cmd {
        const code =
            @as(u32, idx) << 24 |
            @as(u32, ct) << 22 |
            @as(u32, isd) << 21 |
            @as(u32, ie) << 20 |
            @as(u32, ce) << 19 |
            @as(u32, r0) << 18 |
            @as(u32, rt) << 16 |
            @as(u32, rb) << 6 |
            @as(u32, mb) << 5 |
            @as(u32, dir) << 4 |
            @as(u32, ac) << 2 |
            @as(u32, bc) << 1 |
            @as(u32, ra) << 0;

        return .{
            .resp_a = ra,
            .block_count = bc,
            .auto_command = ac,
            .direction = dir,
            .multiblock = mb,
            .resp_b = rb,
            .response_type = rt,
            .res0 = r0,
            .crc_enable = ce,
            .idx_enable = ie,
            .is_data = isd,
            .cmd_type = ct,
            .index = idx,
            .code = code,
        };
    }

    pub inline fn get_index(self: *const Cmd) u32 {
        return @as(u32, self.code);
    }
};

const ReservedCmd = Cmd.init(1, 1, 3, 1, 1, 0xF, 3, 1, 1, 1, 1, 3, 0xF);

const InvalidCmd = ReservedCmd;

const CTGoIdle = Cmd.init(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
const CTSendCide = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT136, 0, 1, 0, 0, 0, 2);
const CTSendRelativeAddr = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48, 0, 1, 0, 0, 0, 3);
const CTIOSetOpCond = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT136, 0, 0, 0, 0, 0, 5);
const CTSelectCard = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48Busy, 0, 1, 0, 0, 0, 7);
const CTSendIfCond = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48, 0, 1, 0, 0, 0, 8);
const CTSetBlockLen = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48, 0, 1, 0, 0, 0, 16);
const CTReadBlock = Cmd.init(0, 0, 0, 1, 0, 0, RespType.RT48, 0, 1, 0, 1, 0, 17);
const CTReadMultiple = Cmd.init(0, 1, 1, 1, 1, 0, RespType.RT48, 0, 1, 0, 1, 0, 18);
const CTOcrCheck = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48, 0, 0, 0, 0, 0, 41);
const CTSendSCR = Cmd.init(0, 0, 0, 1, 0, 0, RespType.RT48, 0, 1, 0, 1, 0, 51);
const CTApp = Cmd.init(0, 0, 0, 0, 0, 0, RespType.RT48, 0, 1, 0, 0, 0, 55);

// TBD This seems unlikely.
const CTWriteBlock = Cmd.init(1, 1, 3, 1, 1, 0xF, 3, 1, 1, 1, 1, 3, 24);
const CTWriteMultiple = Cmd.init(1, 1, 3, 1, 1, 0xF, 3, 1, 1, 1, 1, 3, 25);

const Error = struct {
    const SDECommandTimeout: u32 = 0;
    const SDECommandCrc: u32 = 1;
    const SDECommandEndBit: u32 = 2;
    const SDECommandIndex: u32 = 3;
    const SDEDataTimeout: u32 = 4;
    const SDEDataCrc: u32 = 5;
    const SDEDataEndBit: u32 = 6;
    const SDECurrentLimit: u32 = 7;
    const SDEAutoCmd12: u32 = 8;
    const SDEADma: u32 = 9;
    const SDETuning: u32 = 10;
    const SDERsvd: u32 = 11;
};

const Registers = extern struct {
    arg2: u32,
    block_size_count: u32,
    arg1: u32,
    cmd_xfer_mode: u32,
    response: [4]u32,
    data: u32,
    status: u32,
    control: [2]u32,
    int_flags: u32,
    int_mask: u32,
    int_enable: u32,
    control2: u32,
    cap1: u32,
    cap2: u32,
    res0: [2]u32,
    force_int: u32,
    res1: [7]u32,
    boot_timeout: u32,
    debug_config: u32,
    res2: [2]u32,
    ext_fifo_config: u32,
    ext_fifo_enable: u32,
    tune_step: u32,
    tune_SDR: u32,
    tune_DDR: u32,
    res3: [23]u32,
    spi_int_support: u32,
    res4: [2]u32,
    slot_int_status: u32,
};

fn delayMillis(millis: u32) void {
    spinDelay(10000 * millis);
}

pub fn defineModule(forth: *Forth) !void {
    //try forth.defineStruct("emmc.sdcard", Device, .{
    //        .declarations = true,
    //});
    try forth.defineNamespace(Self, .{
        .{ "enable", "emmc-enable" },
        .{ "set_scr", "emmc-set-scr" },
        .{ "emmc_read", "read" },
    });
}

pub fn init(allocator: Allocator, register_base: u64, gpio: *GPIO, interrupt_controller: *InterruptController, pclock_controller: *PeripheralClockController) !*Self {
    const self = try allocator.create(Self);

    const emmc_clock_rate: u32 = try pclock_controller.clockRateCurrent(CLOCK_EMMC);

    self.* = .{
        .registers = @ptrFromInt(register_base),
        .interrupt_controller = interrupt_controller,
        .gpio = gpio,
        .emmc_clock_rate = emmc_clock_rate,
        .device = undefined,
    };
    return self;
}

inline fn swap_u32(x: u32) u32 {
    return (((x << 24) & 0xff000000) | ((x << 8) & 0x00ff0000) |
        ((x >> 8) & 0x0000ff00) | ((x >> 24) & 0x000000ff));
}

inline fn is_not_zero(value: u32) bool {
    return value != 0;
}

inline fn is_zero(value: u32) bool {
    return value == 0;
}

fn wait_reg_mask(r: *volatile u32, mask: u32, set: bool, timeout: u32) bool {
    for (0..timeout) |_| {
        if (is_not_zero(r.* & mask) == set) {
            _ = printf("wait reg mask returns true!\n");
            return true;
        }
        delayMillis(1);
    }
    _ = printf("wait reg mask returns FALSE!\n");
    return false;
}

// Takes an Error value
fn error_mask(err: u32) u32 {
    const shift: u5 = @truncate(err + 16);
    return @as(u32, 1) << shift;
}

fn set_last_error(self: *Self, intr_val: u32) void {
    self.device.last_error = intr_val & 0xFFFF0000;
    self.device.last_interrupt = intr_val;
}

fn do_data_transfer(self: *Self, cmd: Cmd) bool {
    var wrIrpt: u32 = 0;
    var write = false;

    if (is_not_zero(cmd.direction)) {
        wrIrpt = 1 << 5;
    } else {
        wrIrpt = 1 << 4;
        write = true;
    }

    //u32 *data = (u32 *)device.buffer;
    var data: [*]u32 = self.device.buffer;

    var block: u32 = 0;
    while (block < self.device.transfer_blocks) {
        _ = wait_reg_mask(&self.registers.int_flags, wrIrpt | 0x8000, true, 2000);
        var intr_val = self.registers.int_flags;
        self.registers.int_flags = wrIrpt | 0x8000;

        if ((intr_val & (0xffff0000 | wrIrpt)) != wrIrpt) {
            self.set_last_error(intr_val);
            return false;
        }

        var length: u32 = self.device.block_size;

        if (write) {
            while (length > 0) {
                _ = printf("set scr, writing data %x!\n", data[0]);
                self.registers.data = data[0];
                data += 1;
                length -= 4;
            }
        } else {
            while (length > 0) {
                data[0] = self.registers.data;
                _ = printf("set scr, read data %x!\n", data[0]);
                data += 1;
                length -= 4;
            }
        }
        block += 1;
    }

    return true;
}

fn emmc_issue_command(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    self.device.last_command_value = cmd.code;

    if (self.device.transfer_blocks > 0xFFFF) {
        _ = printf("EMMC_ERR: transferBlocks too large: %d\n", self.device.transfer_blocks);
        return false;
    }

    self.registers.block_size_count = self.device.block_size | (self.device.transfer_blocks << 16);
    self.registers.arg1 = arg;
    self.registers.cmd_xfer_mode = cmd.code;

    delayMillis(10);

    var times: u32 = 0;

    while (times < timeout) {
        const reg: u32 = self.registers.int_flags;

        if (is_not_zero(reg & 0x8001)) {
            break;
        }

        delayMillis(100);
        times += 1;
    }

    if (times >= timeout) {
        //just doing a warn for this because sometimes it's ok.
        _ = printf("EMMC_WARN: emmc_issue_command timed out\n");
        self.device.last_success = false;
        return false;
    }

    var intr_val: u32 = self.registers.int_flags;

    self.registers.int_flags = 0xFFFF0001;

    if ((intr_val & 0xFFFF0001) != 1) {
        _ = printf("EMMC_DEBUG: Error waiting for command interrupt complete: %d\n", cmd.code);
        self.set_last_error(intr_val);
        _ = printf("EMMC_DEBUG: IRQFLAGS: %X - %X - %X\n", self.registers.int_flags, self.registers.status, intr_val);

        self.device.last_success = false;
        _ = printf("Returning false\n");
        return false;
    }

    switch (cmd.response_type) {
        RespType.RT48, RespType.RT48Busy => self.device.last_response[0] = self.registers.response[0],

        RespType.RT136 => {
            self.device.last_response[0] = self.registers.response[0];
            self.device.last_response[1] = self.registers.response[1];
            self.device.last_response[2] = self.registers.response[2];
            self.device.last_response[3] = self.registers.response[3];
        },
        else => {},
    }

    if (cmd.is_data == 1) {
        _ = printf("*** cmd %d is a data command!\n", cmd.code);
        const xfer_result = self.do_data_transfer(cmd);
        _ = printf("xfer result: %d\n", xfer_result);
    }

    if ((cmd.response_type == RespType.RT48Busy) or (cmd.is_data == 1)) {
        _ = wait_reg_mask(&self.registers.int_flags, 0x8002, true, 2000);
        intr_val = self.registers.int_flags;

        self.registers.int_flags = 0xFFFF0002;

        if (((intr_val & 0xFFFF0002) != 2) and ((intr_val & 0xFFFF0002) != 0x100002)) {
            self.set_last_error(intr_val);
            return false;
        }

        self.registers.int_flags = 0xFFFF0002;
    }

    self.device.last_success = true;

    return true;
}

fn get_resp_flag(_: *Self, code: u32) u32 {
    const mask: u32 = (1 << 16) | (1 << 17);
    const masked: u32 = code & mask;
    return masked >> 16;
}

fn get_cmd_id(_: *Self, code: u32) u32 {
    return code >> 24;
}

fn emmc_command(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    //if (is_not_zero(cmd_code & 0x80000000)) {
    //    //The app command flag is set, shoudl use emmc_app_command instead.
    //    _ = printf("EMMC_ERR: COMMAND ERROR NOT APP\n");
    //    return false;
    //}

    self.device.last_command = cmd;
    _ = printf("*** emmc_command, sending command index %d %x\n", cmd.get_index(), self.device.last_command.code);
    _ = printf("*** emmc_command, code %x\n", self.get_cmd_id(self.device.last_command.code));

    _ = printf("Response code: %d\n", self.get_resp_flag(self.device.last_command.code));

    //if (self.device.last_command.cmd_type == Invalid) {
    //    _ = printf("EMMC_ERR: INVALID COMMAND!\n");
    //    return false;
    //}

    return self.emmc_issue_command(self.device.last_command, arg, timeout);
}

const EMMC_CTRL1_RESET_DATA: u32 = (1 << 26);
const EMMC_CTRL1_RESET_CMD: u32 = (1 << 25);
const EMMC_CTRL1_RESET_HOST: u32 = (1 << 24);
const EMMC_CTRL1_RESET_ALL: u32 = EMMC_CTRL1_RESET_DATA | EMMC_CTRL1_RESET_CMD | EMMC_CTRL1_RESET_HOST;

fn reset_command(self: *Self) bool {
    self.registers.control[1] |= EMMC_CTRL1_RESET_CMD;

    for (0..10000) |_| {
        if (is_zero(self.registers.control[1] & EMMC_CTRL1_RESET_CMD)) {
            return true;
        }
        delayMillis(1);
    }

    _ = printf("EMMC_ERR: Command line failed to reset properly: %X\n", self.registers.control[1]);

    return false;
}

fn app_command(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    _ = printf("app_command: %x\n", cmd.get_index());
    if (cmd.index >= 60) {
        _ = printf("EMMC_ERR: INVALID APP COMMAND\n");
        return false;
    }

    self.device.last_command = CTApp;

    var rca: u32 = 0;

    if (is_not_zero(self.device.rca)) {
        rca = self.device.rca << 16;
    }

    if (self.emmc_issue_command(self.device.last_command, rca, 2000)) {
        self.device.last_command = cmd;
        return self.emmc_issue_command(self.device.last_command, arg, timeout);
    }

    return false;
}

fn check_v2_card(self: *Self) bool {
    _ = printf("checking v2 card\n");
    var v2Card: bool = false;

    _ = printf("**sending ifcond cmd\n");
    if (!self.emmc_command(CTSendIfCond, 0x1AA, 200)) {
        _ = printf("ifcond cmd did not work\n");
        if (self.device.last_error == 0) {
            //timeout.
            _ = printf("EMMC_ERR: SEND_IF_COND Timeout\n");
        } else if (is_not_zero(self.device.last_error & (1 << 16))) {
            //timeout command error
            if (!self.reset_command()) {
                return false;
            }

            self.registers.int_flags = error_mask(Error.SDECommandTimeout);
            _ = printf("EMMC_ERR: SEND_IF_COND CMD TIMEOUT\n");
        } else {
            _ = printf("EMMC_ERR: Failure sending SEND_IF_COND\n");
            return false;
        }
    } else {
        if ((self.device.last_response[0] & 0xFFF) != 0x1AA) {
            _ = printf("EMMC_ERR: Unusable SD Card: %X\n", self.device.last_response[0]);
            return false;
        }

        v2Card = true;
    }
    _ = printf("normal return from v2 card %d\n", v2Card);

    return v2Card;
}

fn check_usable_card(self: *Self) bool {
    _ = printf("checking usable card\n");
    _ = printf("sending OPCOND\n");
    if (!self.emmc_command(CTIOSetOpCond, 0, 1000)) {
        if (self.device.last_error == 0) {
            //timeout.
            _ = printf("EMMC_ERR: CTIOSetOpCond Timeout\n");
        } else if (is_not_zero(self.device.last_error & (1 << 16))) {
            //timeout command error
            //this is a normal expected error and calling the reset command will fix it.
            if (!self.reset_command()) {
                return false;
            }

            self.registers.int_flags = error_mask(Error.SDECommandTimeout);
        } else {
            _ = printf("EMMC_ERR: SDIO Card not supported\n");
            return false;
        }
    }

    return true;
}

fn check_sdhc_support(self: *Self, v2_card: bool) bool {
    var card_busy = true;

    while (card_busy) {
        var v2_flags: u32 = 0;

        if (v2_card) {
            v2_flags |= (1 << 30); //SDHC Support
        }

        if (!self.app_command(CTOcrCheck, 0x00FF8000 | v2_flags, 2000)) {
            _ = printf("EMMC_ERR: APP CMD 41 FAILED 2nd\n");
            return false;
        }

        if (is_not_zero(self.device.last_response[0] >> 31 & 1)) {
            self.device.ocr = @truncate(self.device.last_response[0] >> 8 & 0xFFFF);
            self.device.sdhc = ((self.device.last_response[0] >> 30) & 1) != 0;
            card_busy = false;
        } else {
            _ = printf("EMMC_DEBUG: SLEEPING: %X\n", self.device.last_response[0]);
            delayMillis(500);
        }
    }

    return true;
}

fn check_ocr(self: *Self) bool {
    var passed = false;

    for (0..5) |i| {
        _ = printf("\n checkin ocr, loop %d\n", i);
        if (!self.app_command(CTOcrCheck, 0, 2000)) {
            _ = printf("EMMC_WARN: APP CMD OCR CHECK TRY %d FAILED\n", i + 1);
            passed = false;
        } else {
            passed = true;
        }

        if (passed) {
            break;
        }

        return false;
    }

    if (!passed) {
        _ = printf("EMMC_ERR: APP CMD 41 FAILED\n");
        return false;
    }

    self.device.ocr = @truncate(self.device.last_response[0] >> 8 & 0xFFFF);

    _ = printf("MEMORY OCR: %X\n", self.device.ocr);

    return true;
}

fn check_rca(self: *Self) bool {
    if (!self.emmc_command(CTSendCide, 0, 2000)) {
        _ = printf("EMMC_ERR: Failed to send CID\n");
        return false;
    }

    _ = printf("EMMC_DEBUG: CARD ID: %X.%X.%X.%X\n", self.device.last_response[0], self.device.last_response[1], self.device.last_response[2], self.device.last_response[3]);

    if (!self.emmc_command(CTSendRelativeAddr, 0, 2000)) {
        _ = printf("EMMC_ERR: Failed to send Relative Addr\n");
        return false;
    }

    self.device.rca = (self.device.last_response[0] >> 16) & 0xFFFF;

    _ = printf("EMMC_DEBUG: RCA: %X\n", self.device.rca);

    _ = printf("EMMC_DEBUG: CRC_ERR: %d\n", (self.device.last_response[0] >> 15) & 1);
    _ = printf("EMMC_DEBUG: CMD_ERR: %d\n", (self.device.last_response[0] >> 14) & 1);
    _ = printf("EMMC_DEBUG: GEN_ERR: %d\n", (self.device.last_response[0] >> 13) & 1);
    _ = printf("EMMC_DEBUG: STS_ERR: %d\n", (self.device.last_response[0] >> 9) & 1);
    _ = printf("EMMC_DEBUG: READY  : %d\n", (self.device.last_response[0] >> 8) & 1);

    if (is_zero((self.device.last_response[0] >> 8) & 1)) {
        _ = printf("EMMC_ERR: Failed to read RCA\n");
        return false;
    }

    return true;
}

fn select_card(
    self: *Self,
) bool {
    if (!self.emmc_command(CTSelectCard, self.device.rca << 16, 2000)) {
        _ = printf("EMMC_ERR: Failed to select card\n");
        return false;
    }

    _ = printf("EMMC_DEBUG: Selected Card\n");

    var status: u32 = (self.device.last_response[0] >> 9) & 0xF;

    if ((status != 3) and (status != 4)) {
        _ = printf("EMMC_ERR: Invalid Status: %d\n", status);
        return false;
    }

    _ = printf("EMMC_DEBUG: Status: %d\n", status);

    return true;
}

pub fn set_scr(self: *Self) bool {
    _ = printf("** setting scr\n");
    if (!self.device.sdhc) {
        if (!self.emmc_command(CTSetBlockLen, 512, 2000)) {
            _ = printf("EMMC_ERR: *** Failed to set block len\n");
            return false;
        }
    }

    var bsc = self.registers.block_size_count;
    bsc &= ~@as(u32, 0xFFF); //mask off bottom bits
    bsc |= @as(u32, 0x200); //set bottom bits to 512
    self.registers.block_size_count = bsc;

    self.device.buffer = &self.device.scr.scr;
    self.device.block_size = 8;
    self.device.transfer_blocks = 1;

    if (!self.app_command(CTSendSCR, 0, 30000)) {
        _ = printf("EMMC_ERR: ***Failed to send SCR\n");
        return false;
    }

    _ = printf("EMMC_DEBUG: GOT SRC: SCR0: %X SCR1: %X BWID: %X\n", self.device.scr.scr[0], self.device.scr.scr[1], self.device.scr.bus_widths);

    self.device.block_size = 512;

    var scr0: u32 = swap_u32(self.device.scr.scr[0]);
    self.device.scr.version = 0xFFFFFFFF;
    var spec: u32 = (scr0 >> (56 - 32)) & 0xf;
    var spec3: u32 = (scr0 >> (47 - 32)) & 0x1;
    var spec4: u32 = (scr0 >> (42 - 32)) & 0x1;

    if (spec == 0) {
        self.device.scr.version = 1;
    } else if (spec == 1) {
        self.device.scr.version = 11;
    } else if (spec == 2) {
        if (spec3 == 0) {
            self.device.scr.version = 2;
        } else if (spec3 == 1) {
            if (spec4 == 0) {
                self.device.scr.version = 3;
            }
            if (spec4 == 1) {
                self.device.scr.version = 4;
            }
        }
    }

    _ = printf("EMMC_DEBUG: SCR Version: %d\n", self.device.scr.version);

    return true;
}

fn emmc_card_reset(self: *Self) bool {
    self.registers.control[1] = EMMC_CTRL1_RESET_HOST;

    _ = printf("EMMC_DEBUG: Card resetting...\n");

    if (!wait_reg_mask(&self.registers.control[1], EMMC_CTRL1_RESET_ALL, false, 2000)) {
        _ = printf("EMMC_ERR: Card reset timeout!\n");
        return false;
    }

    if (!self.emmc_setup_clock()) {
        return false;
    }

    //All interrupts go to interrupt register.
    self.registers.int_enable = 0;
    self.registers.int_flags = 0xFFFFFFFF;
    self.registers.int_mask = 0xFFFFFFFF;

    delayMillis(203);

    self.device.transfer_blocks = 0;
    self.device.last_command_value = 0;
    self.device.last_success = false;
    self.device.block_size = 0;

    if (!self.emmc_command(CTGoIdle, 0, 2000)) {
        _ = printf("EMMC_ERR: NO GO_IDLE RESPONSE\n");
        return false;
    }

    _ = printf("EMMC go idle done\n");

    _ = printf("checking v2 card\n");
    delayMillis(100);
    const v2_card = self.check_v2_card();

    _ = printf("checking usable card\n");
    delayMillis(100);
    if (!self.check_usable_card()) {
        _ = printf("***card not usuable\n");
        return false;
    }

    _ = printf("checking ocr\n");
    delayMillis(100);
    if (!self.check_ocr()) {
        return false;
    }

    _ = printf("checking sdhc support\n");
    delayMillis(100);
    if (!self.check_sdhc_support(v2_card)) {
        return false;
    }

    delayMillis(100);
    _ = printf("changing clock rate\n");
    _ = self.switch_clock_rate(self.device.base_clock, SD_CLOCK_NORMAL);

    //delayMillis(10);

    delayMillis(100);
    if (!self.check_rca()) {
        return false;
    }

    delayMillis(100);
    if (!self.select_card()) {
        return false;
    }

    //delayMillis(100);
    //if (!self.set_scr()) {
    //    return false;
    //}

    //enable all interrupts
    self.registers.int_flags = 0xFFFFFFFF;

    _ = printf("EMMC_DEBUG: Card reset!\n");

    return true;
}

//int emmc_io_read(io_self.device *dev, void *b, u32 size) {
//    return emmc_read((u8 *)b, size);
//}
//
//void emmc_io_seek(io_self.device *dev, u64 offset) {
//    return emmc_seek(offset);
//}

// TBD u32? for buffer
//
fn do_data_command(self: *Self, write: bool, b: [*]u32, bsize: u32, bn: u32) bool {
    var block_no = bn;
    if (!self.device.sdhc) {
        block_no *= 512;
    }

    if (bsize < self.device.block_size) {
        _ = printf("EMMC_ERR: INVALID BLOCK SIZE: %d %d\n", bsize, self.device.block_size);
        return false;
    }

    self.device.transfer_blocks = bsize / self.device.block_size;

    if ((bsize % self.device.block_size) != 0) {
        _ = printf("EMMC_ERR: BAD BLOCK SIZE\n");
        return false;
    }

    self.device.buffer = b;

    var command = CTReadBlock;

    if (write and (self.device.transfer_blocks > 1)) {
        command = CTWriteMultiple;
    } else if (write) {
        command = CTWriteBlock;
    } else if ((!write) and (self.device.transfer_blocks > 1)) {
        command = CTReadMultiple;
    }

    var retry_count: u32 = 0;
    var max_retries: u32 = 3;

    _ = printf("EMMC_DEBUG: Sending command: %d\n", @as(u32, command.index));

    while (retry_count < max_retries) {
        if (self.emmc_command(command, block_no, 5000)) {
            break;
        }

        retry_count += 1;
        if (retry_count < max_retries) {
            _ = printf("EMMC_WARN: Retrying data command %d\n", retry_count);
        } else {
            _ = printf("EMMC_ERR: Giving up data command\n");
            return false;
        }
    }

    return true;
}

// tbd u32?
fn do_read(self: *Self, b: [*]u32, bsize: u32, block_no: u32) i64 {
    //TODO ENSURE DATA MODE...

    if (!self.do_data_command(false, b, bsize, block_no)) {
        _ = printf("EMMC_ERR: do_data_command failed\n");
        return -1;
    }

    return bsize;
}

// rbd u32?
pub fn emmc_read(self: *Self, buffer: [*]u32, size: u32) i64 {
    _ = printf("** emmc read buf %x size: %d\n", buffer, size);
    if (self.device.offset % 512 != 0) {
        _ = printf("EMMC_ERR: INVALID OFFSET: %d\n", self.device.offset);
        return -1;
    }

    const block: u32 = @intCast(self.device.offset / 512);

    const r = self.do_read(buffer, size, block);

    if (r != size) {
        _ = printf("EMMC_ERR: READ FAILED: %d\n", r);
        return -1;
    }

    return size;
}

pub fn emmc_seek(self: *Self, offset: u32) void {
    self.device.offset = offset;
}

pub fn enable(self: *Self) bool {
    self.gpio.selectFunction(34, GPIO.FunctionSelect.Input);
    self.gpio.selectFunction(35, GPIO.FunctionSelect.Input);
    self.gpio.selectFunction(36, GPIO.FunctionSelect.Input);
    self.gpio.selectFunction(37, GPIO.FunctionSelect.Input);
    self.gpio.selectFunction(38, GPIO.FunctionSelect.Input);
    self.gpio.selectFunction(39, GPIO.FunctionSelect.Input);

    self.gpio.selectFunction(48, GPIO.FunctionSelect.Alt3);
    self.gpio.selectFunction(49, GPIO.FunctionSelect.Alt3);
    self.gpio.selectFunction(50, GPIO.FunctionSelect.Alt3);
    self.gpio.selectFunction(51, GPIO.FunctionSelect.Alt3);
    self.gpio.selectFunction(52, GPIO.FunctionSelect.Alt3);

    self.device.transfer_blocks = 0;
    self.device.last_command_value = 0;
    self.device.last_success = false;
    self.device.block_size = 0;
    self.device.sdhc = false;
    self.device.ocr = 0;
    self.device.rca = 0;
    self.device.offset = 0;
    self.device.base_clock = 0;

    var success = false;
    for (0..10) |_| {
        success = self.emmc_card_reset();

        if (success) {
            break;
        }

        delayMillis(100);
        _ = printf("EMMC_WARN: Failed to reset card, trying again...\n");
    }

    if (!success) {
        return false;
    }

    return true;
}

fn get_clock_divider(_: *Self, base_clock: u32, target_rate: u32) u32 {
    var target_div: u32 = 1;

    if (target_rate <= base_clock) {
        target_div = base_clock / target_rate;

        if (is_not_zero(base_clock % target_rate)) {
            target_div = 0;
        }
    }

    var div: i64 = -1;

    var fb: u5 = 31;
    for (0..31) |_| {
        var bt: u32 = @as(u32, 1) << fb;

        if (is_not_zero(target_div & bt)) {
            div = fb;
            target_div &= ~(bt);

            if (is_not_zero(target_div)) {
                div += 1;
            }

            break;
        }
        fb -= 1;
    }

    if (div == -1) {
        div = 31;
    }

    if (div >= 32) {
        div = 31;
    }

    if (div != 0) {
        div = @as(u32, 1) << (@as(u5, @intCast(div)) - 1);
    }

    if (div >= 0x400) {
        div = 0x3FF;
    }

    const udiv: u32 = @intCast(div);
    var freqSel: u32 = udiv & 0xff;
    var upper: u32 = (udiv >> 8) & 0x3;
    var ret: u32 = (freqSel << 8) | (upper << 6) | (0 << 5);

    return ret;
}

const EMMC_STATUS_DAT_INHIBIT: u32 = (1 << 1);
const EMMC_STATUS_CMD_INHIBIT: u32 = (1 << 0);

const EMMC_CTRL1_CLK_GENSEL: u32 = (1 << 5);
const EMMC_CTRL1_CLK_ENABLE: u32 = (1 << 2);
const EMMC_CTRL1_CLK_STABLE: u32 = (1 << 1);
const EMMC_CTRL1_CLK_INT_EN: u32 = (1 << 0);

fn switch_clock_rate(self: *Self, base_clock: u32, target_rate: u32) bool {
    const divider: u32 = self.get_clock_divider(base_clock, target_rate);

    while (is_not_zero(self.registers.status & (EMMC_STATUS_CMD_INHIBIT | EMMC_STATUS_DAT_INHIBIT))) {
        delayMillis(1);
    }

    const c1: u32 = self.registers.control[1] & ~EMMC_CTRL1_CLK_ENABLE;

    self.registers.control[1] = c1;

    delayMillis(3);

    self.registers.control[1] = (c1 | divider) & ~@as(u32, 0xFFE0);

    delayMillis(3);

    self.registers.control[1] = c1 | EMMC_CTRL1_CLK_ENABLE;

    delayMillis(3);

    return true;
}

const SD_CLOCK_ID: u32 = 400000;
const SD_CLOCK_NORMAL: u32 = 25000000;
const SD_CLOCK_HIGH: u32 = 50000000;
const SD_CLOCK_100: u32 = 100000000;
const SD_CLOCK_208: u32 = 208000000;

fn emmc_setup_clock(self: *Self) bool {
    self.registers.control2 = 0;

    const rate: u32 = self.emmc_clock_rate;

    var n = self.registers.control[1];
    n |= EMMC_CTRL1_CLK_INT_EN;
    n |= self.get_clock_divider(rate, SD_CLOCK_ID);
    n &= ~(@as(u32, 0xf) << 16);
    n |= (11 << 16);

    self.registers.control[1] = n;

    if (!wait_reg_mask(&self.registers.control[1], EMMC_CTRL1_CLK_STABLE, true, 2000)) {
        _ = printf("EMMC_ERR: SD CLOCK NOT STABLE\n");
        return false;
    }

    delayMillis(30);

    //enabling the clock
    self.registers.control[1] |= 4;

    delayMillis(30);

    return true;
}

registers: *volatile Registers,
interrupt_controller: *InterruptController,
gpio: *GPIO,
emmc_clock_rate: u32 = 0,
hostVersion: u32 = 0,
device: Device,
