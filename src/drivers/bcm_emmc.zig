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

pub fn defineModule(forth: *Forth) !void {
    try forth.defineStruct("emmc.sdcard", Device, .{
        .declarations = true,
    });
    try forth.defineNamespace(Self, .{
        .{ "emmcEnable", "emmc-enable" },
        .{ "emmcRead", "emmc-read" },
        .{ "emmcReset", "emmc-reset" },
    });
}

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
    buffer: [*]u32 = undefined,
    base_clock: u32 = 0,
    last_error: u32 = 0,
    last_interrupt: u32 = 0,
    scr: ScrRegister = undefined,
};

const Resp = struct {
    const RInvalid: u32 = 0xface;

    const RNone: u32 = 0;
    const R136: u32 = 1;
    const R48: u32 = 2;
    const R48Busy: u32 = 3;
};

// The docs call these values the cmd type, but really
// they tell us how the command affects data transfer.
const CmdType = enum(u32) {
    Normal = 0,
    Suspend = 1,
    Resume = 2,
    Abort = 3,
};

// Direction of data transfer in a command.
const Dir = enum(i32) {
    FromHost = 0,
    FromCard = 1,
};

// Command that gets sent to emmc controller.
// Only the code actually gets sent to the controller.
// All the other data are just flags that go into building
// the amazing complex bits of the command.
const Cmd = struct {
    resp_a: u1,
    block_count: u1,
    auto_command: u2,
    direction: Dir,
    multiblock: u1,
    resp_b: u10,
    response_type: u2,
    crc_enable: bool,
    idx_enable: bool,
    is_data: bool,
    cmd_type: CmdType,
    index: u6,

    code: u32,

    inline fn bool_to_u1(b: bool) u1 {
        return if (b) 1 else 0;
    }

    pub fn init(ra: u1, bc: u1, ac: u2, dir: Dir, mb: u1, rb: u10, rt: u2, ce: bool, ie: bool, isd: bool, ct: CmdType, idx: u6) Cmd {
        const code =
            @as(u32, idx) << 24 |
            @intFromEnum(ct) << 22 |
            @as(u32, bool_to_u1(isd)) << 21 |
            @as(u32, bool_to_u1(ie)) << 20 |
            @as(u32, bool_to_u1(ce)) << 19 |
            @as(u32, rt) << 16 |
            @as(u32, rb) << 6 |
            @as(u32, mb) << 5 |
            @intFromEnum(dir) << 4 |
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
            .crc_enable = ce,
            .idx_enable = ie,
            .is_data = isd,
            .cmd_type = ct,
            .index = idx,
            .code = code,
        };
    }

    pub inline fn get_index(self: *const Cmd) u32 {
        return @as(u32, self.index);
    }

    // Commands with an index >= 32 need to be preceeded
    // by an App Cmd. This seems to be some kind of extension
    // prefix.
    pub fn needs_app_cmd(self: *const Cmd) bool {
        return self.index >= 32;
    }
};

// These are the predefined commands used to interact with the emmc controller
// and eventually the SD card.
const CmdGoIdle = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, 0, false, false, false, CmdType.Normal, 0);
const CmdResetHost = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, 0, false, false, false, CmdType.Normal, 1);
const CmdResetCmd = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, 0, false, false, false, CmdType.Normal, 2);
const CmdSendCide = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R136, true, false, false, CmdType.Normal, 2);
const CmdSendRelativeAddr = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48, true, false, false, CmdType.Normal, 3);
const CmdResetData = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, 0, false, false, false, CmdType.Normal, 4);
const CmdIOSetOpCond = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R136, false, false, false, CmdType.Normal, 5);
const CmdSelectCard = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48Busy, true, false, false, CmdType.Normal, 7);
const CmdResetAll = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, 0, false, false, false, CmdType.Normal, 7);
const CmdSendIfCond = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48, true, false, false, CmdType.Normal, 8);
const CmdSetBlockLen = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48, true, false, false, CmdType.Normal, 16);
const CmdReadBlock = Cmd.init(0, 0, 0, Dir.FromCard, 0, 0, Resp.R48, true, false, true, CmdType.Normal, 17);
const CmdReadMultiple = Cmd.init(0, 1, 1, Dir.FromCard, 1, 0, Resp.R48, true, false, true, CmdType.Normal, 18);
const CmdOcrCheck = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48, false, false, false, CmdType.Normal, 41);
const CmdSendSCR = Cmd.init(0, 0, 0, Dir.FromCard, 0, 0, Resp.R48, true, false, true, CmdType.Normal, 51);
const CmdApp = Cmd.init(0, 0, 0, Dir.FromHost, 0, 0, Resp.R48, true, false, false, CmdType.Normal, 55);

const CmdWriteBlock = Cmd.init(1, 1, 3, Dir.FromCard, 1, 0xF, 3, true, true, true, CmdType.Abort, 24);
const CmdWriteMultiple = Cmd.init(1, 1, 3, Dir.FromCard, 1, 0xF, 3, true, true, true, CmdType.Abort, 25);

// Errors that we get back from the emmc controller.
const Error = struct {
    const Timeout: u32 = 0;
    const Crc: u32 = 1;
    const EndBit: u32 = 2;
    const Index: u32 = 3;
    const DataTimeout: u32 = 4;
    const DataCrc: u32 = 5;
    const DataEndBit: u32 = 6;
    const CurrentLimit: u32 = 7;
    const AutoCmd12: u32 = 8;
    const ADma: u32 = 9;
    const Tuning: u32 = 10;
    const Rsvd: u32 = 11;
};

// These are the registers that we use to physically interact with
// the controller.
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

// Various sd card clock frequencies.

const SDClock = struct {
    const ID: u32 = 400000;
    const NORMAL: u32 = 25000000;
    const HIGH: u32 = 50000000;
    const FRQ_100: u32 = 100000000;
    const FRQ_208: u32 = 208000000;
};

// Flags for status register.
const StatusRegister = struct {
    const DataInhibit: u32 = (1 << 1);
    const CmdInhibit: u32 = (1 << 1);
};

// Flags for the control registers.
const ControlRegister = struct {
    const GenSel: u32 = (1 << 5);
    const ClockEnable: u32 = (1 << 2);
    const ClockStable: u32 = (1 << 1);
    const ClockIntEnable: u32 = (1 << 0);
};

registers: *volatile Registers,
interrupt_controller: *InterruptController,
gpio: *GPIO,
emmc_clock_rate: u32 = 0,
hostVersion: u32 = 0,
device: Device,

// TBD replace this with something more legitimate.
fn delayMillis(millis: u32) void {
    spinDelay(10000 * millis);
}

// This is the boot time initialization, just sets up the data
// structures but doesn't set up the hardware.
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

pub fn emmcEnable(self: *Self) bool {
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
    self.device.base_clock = 0;

    var success = false;
    for (0..4) |_| {
        success = self.emmcReset();

        if (success) {
            break;
        }

        delayMillis(100);
        _ = printf("emmc: Failed to reset card, trying again...\n");
    }

    if (!success) {
        return false;
    }

    return true;
}

// Read a block of data from the card.
pub fn emmcRead(self: *Self, buffer: [*]u32, size: u32, block: u32) i64 {
    _ = printf("emmc: read block: %x, buf %x size: %d\n", block, buffer, size);

    const r = self.doRead(buffer, size, block);

    if (r != size) {
        _ = printf("emmc: read failed: %d %d\n", r, size);
        return -1;
    }

    return size;
}

// Reset the whole emmc controller.
pub fn emmcReset(self: *Self) bool {
    self.registers.control[1] = CmdResetHost.code;

    _ = printf("emmc: Reset\n");

    if (!waitRegister(&self.registers.control[1], CmdResetAll.code, false, 2000)) {
        _ = printf("emmc: reset timeout!\n");
        return false;
    }

    if (!self.setupClock()) {
        return false;
    }

    // Turn off interrupts.
    self.registers.int_enable = 0;
    self.registers.int_flags = 0xFFFFFFFF;
    self.registers.int_mask = 0xFFFFFFFF;

    delayMillis(203);

    self.device.transfer_blocks = 0;
    self.device.last_command_value = 0;
    self.device.last_success = false;
    self.device.block_size = 0;

    if (!self.emmcCommand(CmdGoIdle, 0, 2000)) {
        return false;
    }

    delayMillis(100);
    const v2_card = self.checkV2Card();

    delayMillis(100);
    if (!self.checkUsableCard()) {
        return false;
    }

    delayMillis(100);
    if (!self.checkOCR()) {
        return false;
    }

    delayMillis(100);
    if (!self.checkSDHCSupport(v2_card)) {
        return false;
    }

    delayMillis(100);
    _ = self.switchClockRate(self.device.base_clock, SDClock.NORMAL);

    delayMillis(100);
    if (!self.checkRCA()) {
        return false;
    }

    delayMillis(100);
    if (!self.selectCard()) {
        return false;
    }

    delayMillis(100);
    if (!self.setSCR()) {
        return false;
    }

    self.registers.int_flags = 0xFFFFFFFF;

    _ = printf("emmc: Reset complete.\n");

    return true;
}

fn setLastError(self: *Self, intr_val: u32) void {
    self.device.last_error = intr_val & 0xFFFF0000;
    self.device.last_interrupt = intr_val;
}

// Synchronously transfer data to/from sdcard.
fn doDataTransfer(self: *Self, cmd: Cmd) bool {
    var wrIrpt: u32 = 0;
    var write = false;

    if (cmd.direction == Dir.FromCard) {
        wrIrpt = 1 << 5;
    } else {
        wrIrpt = 1 << 4;
        write = true;
    }

    var data: [*]u32 = self.device.buffer;

    var block: u32 = 0;
    while (block < self.device.transfer_blocks) {
        _ = waitRegister(&self.registers.int_flags, wrIrpt | 0x8000, true, 2000);
        var intr_val = self.registers.int_flags;
        self.registers.int_flags = wrIrpt | 0x8000;

        if ((intr_val & (0xffff0000 | wrIrpt)) != wrIrpt) {
            self.setLastError(intr_val);
            return false;
        }

        var length: u32 = self.device.block_size;

        if (write) {
            while (length > 0) {
                _ = printf("emmc: set scr %x\n", data[0]);
                self.registers.data = data[0];
                data += 1;
                length -= 4;
            }
        } else {
            while (length > 0) {
                data[0] = self.registers.data;
                data += 1;
                length -= 4;
            }
        }
        block += 1;
    }

    return true;
}

// Issue a command exactly as specified, wait for the response.
fn issueCommand(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    self.device.last_command_value = cmd.code;

    if (self.device.transfer_blocks > 0xFFFF) {
        _ = printf("emmc: transferBlocks too large: %d\n", self.device.transfer_blocks);
        return false;
    }

    self.registers.block_size_count = self.device.block_size | (self.device.transfer_blocks << 16);
    self.registers.arg1 = arg;
    self.registers.cmd_xfer_mode = cmd.code;

    delayMillis(10);

    var times: u32 = 0;

    while (times < timeout) {
        const reg: u32 = self.registers.int_flags;

        if (isNotZero(reg & 0x8001)) {
            break;
        }

        delayMillis(100);
        times += 1;
    }

    if (times >= timeout) {
        //just doing a warn for this because sometimes it's ok.
        _ = printf("emmc: command timed out.\n");
        self.device.last_success = false;
        return false;
    }

    var intr_val: u32 = self.registers.int_flags;

    self.registers.int_flags = 0xFFFF0001;

    if ((intr_val & 0xFFFF0001) != 1) {
        _ = printf("emmc: timeout waiting for command interrupt complete: %d\n", cmd.code);
        self.setLastError(intr_val);
        self.device.last_success = false;
        return false;
    }

    switch (cmd.response_type) {
        Resp.R48, Resp.R48Busy => self.device.last_response[0] = self.registers.response[0],

        Resp.R136 => {
            self.device.last_response[0] = self.registers.response[0];
            self.device.last_response[1] = self.registers.response[1];
            self.device.last_response[2] = self.registers.response[2];
            self.device.last_response[3] = self.registers.response[3];
        },
        else => {},
    }

    if (cmd.is_data) {
        const xfer_result = self.doDataTransfer(cmd);
        if (!xfer_result) {
            _ = printf("emmc: data transfer failed.\n");
            return false;
        }
    }

    if ((cmd.response_type == Resp.R48Busy) or cmd.is_data) {
        _ = waitRegister(&self.registers.int_flags, 0x8002, true, 2000);
        intr_val = self.registers.int_flags;

        self.registers.int_flags = 0xFFFF0002;

        if (((intr_val & 0xFFFF0002) != 2) and ((intr_val & 0xFFFF0002) != 0x100002)) {
            self.setLastError(intr_val);
            return false;
        }

        self.registers.int_flags = 0xFFFF0002;
    }

    self.device.last_success = true;

    return true;
}

fn getResponseFlag(_: *Self, code: u32) u32 {
    const mask: u32 = (1 << 16) | (1 << 17);
    const masked: u32 = code & mask;
    return masked >> 16;
}

// Issue a command, handle the case where we need to send an APP command first.
fn emmcCommand(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    _ = printf("emmc: sending command %d.\n", cmd.get_index());
    var result = false;
    if (cmd.needs_app_cmd()) {
        result = self.issueAppCommand(cmd, arg, timeout);
    } else {
        result = self.issueNormalCommand(cmd, arg, timeout);
    }
    if (!result) {
        _ = printf("emmc: command failed: %d => %d\n", cmd.get_index());
    }
    return result;
}

// Issue a command that does not require a APP command.
fn issueNormalCommand(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    self.device.last_command = cmd;
    return self.issueCommand(self.device.last_command, arg, timeout);
}

// Issue a command that requires an APP command to be sent first.
fn issueAppCommand(self: *Self, cmd: Cmd, arg: u32, timeout: u32) bool {
    self.device.last_command = CmdApp;

    var rca: u32 = 0;

    if (isNotZero(self.device.rca)) {
        rca = self.device.rca << 16;
    }

    if (self.issueCommand(self.device.last_command, rca, 2000)) {
        self.device.last_command = cmd;
        return self.issueCommand(self.device.last_command, arg, timeout);
    }

    return false;
}

// Issue a reset command, a special, simpler case.
fn issueResetCommand(self: *Self) bool {
    _ = printf("emmc: issue reset command.\n");
    self.registers.control[1] |= CmdResetCmd.code;

    for (0..1000) |_| {
        if (isZero(self.registers.control[1] & CmdResetCmd.code)) {
            _ = printf("emmc: reset complete.\n");
            return true;
        }
        delayMillis(1);
    }

    _ = printf("sdcard: failed to reset\n");
    return false;
}

// Determine if we have a version 2 card.
fn checkV2Card(self: *Self) bool {
    var v2Card: bool = false;

    if (!self.emmcCommand(CmdSendIfCond, 0x1AA, 200)) {
        _ = printf("ifcond cmd did not work\n");
        if (self.device.last_error == 0) {
            _ = printf("emmc: send_if_cond timeout\n");
        } else if (isNotZero(self.device.last_error & (1 << 16))) {
            if (!self.issueResetCommand()) {
                return false;
            }

            self.registers.int_flags = errorMask(Error.Timeout);
            _ = printf("emmc: send_if_cond cmd timeout\n");
        } else {
            _ = printf("emmc: failure sending send_if_cond\n");
            return false;
        }
    } else {
        if ((self.device.last_response[0] & 0xFFF) != 0x1AA) {
            _ = printf("emmc: Unusable SD Card: %X\n", self.device.last_response[0]);
            return false;
        }

        v2Card = true;
    }

    return v2Card;
}

// Determine if we have a usable card.
fn checkUsableCard(self: *Self) bool {
    if (!self.emmcCommand(CmdIOSetOpCond, 0, 1000)) {
        if (self.device.last_error == 0) {
            return false; // Timeout.
        } else if (isNotZero(self.device.last_error & (1 << 16))) {
            //timeout command error
            //this is a normal expected error and calling the reset command will fix it.
            if (!self.issueResetCommand()) {
                return false;
            }
            self.registers.int_flags = errorMask(Error.Timeout);
        } else {
            return false;
        }
    }

    return true;
}

// Check if we support sdhc.
fn checkSDHCSupport(self: *Self, v2_card: bool) bool {
    const v2_flags: u32 = if (v2_card) (1 << 30) else 0;

    for (0..10) |_| {
        if (!self.emmcCommand(CmdOcrCheck, 0x00FF8000 | v2_flags, 2000)) {
            _ = printf("emmc: CmdOcrCheck failed 2nd\n");
            return false;
        }

        if (isNotZero(self.device.last_response[0] >> 31 & 1)) {
            self.device.ocr = @truncate(self.device.last_response[0] >> 8 & 0xFFFF);
            self.device.sdhc = ((self.device.last_response[0] >> 30) & 1) != 0;
            return true;
        } else {
            delayMillis(500);
        }
    }

    // Timed out.
    return false;
}

// Check OCR.
fn checkOCR(self: *Self) bool {
    if (!self.emmcCommand(CmdOcrCheck, 0, 2000)) {
        _ = printf("emmc: App cmd ocr check failed\n");
        return false;
    }

    self.device.ocr = @truncate(self.device.last_response[0] >> 8 & 0xFFFF);
    return true;
}

// Check RCA.
fn checkRCA(self: *Self) bool {
    if (!self.emmcCommand(CmdSendCide, 0, 2000)) {
        _ = printf("emmc: Failed to send CID\n");
        return false;
    }

    if (!self.emmcCommand(CmdSendRelativeAddr, 0, 2000)) {
        _ = printf("emmc: Failed to send Relative Addr\n");
        return false;
    }

    self.device.rca = (self.device.last_response[0] >> 16) & 0xFFFF;

    if (isZero((self.device.last_response[0] >> 8) & 1)) {
        _ = printf("emmc: Failed to read RCA\n");
        return false;
    }

    return true;
}

// Select the card speficied by the RCA value.
fn selectCard(self: *Self) bool {
    if (!self.emmcCommand(CmdSelectCard, self.device.rca << 16, 2000)) {
        _ = printf("emmc: Failed to select card\n");
        return false;
    }

    var status: u32 = (self.device.last_response[0] >> 9) & 0xF;

    if ((status != 3) and (status != 4)) {
        _ = printf("emmc: Invalid status: %d\n", status);
        return false;
    }

    return true;
}

fn setSCR(self: *Self) bool {
    if (!self.device.sdhc) {
        if (!self.emmcCommand(CmdSetBlockLen, 512, 2000)) {
            _ = printf("emmc: Failed to set block len\n");
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

    if (!self.emmcCommand(CmdSendSCR, 0, 30000)) {
        _ = printf("emmc: Failed to send scr\n");
        return false;
    }

    _ = printf("emmc: scr0: %x scr1: %x bwid: %x\n", self.device.scr.scr[0], self.device.scr.scr[1], self.device.scr.bus_widths);

    self.device.block_size = 512;

    const scr_value = self.device.scr.scr[0];
    var scr0 =
        ((scr_value << 24) & 0xff000000) |
        ((scr_value << 8) & 0x00ff0000) |
        ((scr_value >> 8) & 0x0000ff00) |
        ((scr_value >> 24) & 0x000000ff);

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

    _ = printf("emmc: scr version: %d\n", self.device.scr.version);

    return true;
}

fn doDataCommand(self: *Self, write: bool, b: [*]u32, bsize: u32, bn: u32) bool {
    var block_no = bn;
    if (!self.device.sdhc) {
        block_no *= 512;
    }

    if (bsize < self.device.block_size) {
        _ = printf("emmc: INVALID BLOCK SIZE: %d %d\n", bsize, self.device.block_size);
        return false;
    }

    self.device.transfer_blocks = bsize / self.device.block_size;

    if ((bsize % self.device.block_size) != 0) {
        _ = printf("emmc: BAD BLOCK SIZE\n");
        return false;
    }

    self.device.buffer = b;

    var command = CmdReadBlock;

    if (write and (self.device.transfer_blocks > 1)) {
        command = CmdWriteMultiple;
    } else if (write) {
        command = CmdWriteBlock;
    } else if ((!write) and (self.device.transfer_blocks > 1)) {
        command = CmdReadMultiple;
    }

    var retry_count: u32 = 0;
    var max_retries: u32 = 3;

    _ = printf("emmc: Sending command: %d\n", @as(u32, command.index));

    while (retry_count < max_retries) {
        if (self.emmcCommand(command, block_no, 5000)) {
            break;
        }

        retry_count += 1;
        if (retry_count < max_retries) {
            _ = printf("emmc: Retrying data command %d\n", retry_count);
        } else {
            _ = printf("emmc: Giving up data command\n");
            return false;
        }
    }

    return true;
}

fn doRead(self: *Self, b: [*]u32, bsize: u32, block_no: u32) i64 {
    //TODO ENSURE DATA MODE...

    if (!self.doDataCommand(false, b, bsize, block_no)) {
        _ = printf("emmc: doDataCommand failed\n");
        return -1;
    }

    return bsize;
}

fn getClockDivider(_: *Self, base_clock: u32, target_rate: u32) u32 {
    var target_div: u32 = 1;

    if (target_rate <= base_clock) {
        target_div = base_clock / target_rate;

        if (isNotZero(base_clock % target_rate)) {
            target_div = 0;
        }
    }

    var div: i64 = -1;

    var fb: u5 = 31;
    for (0..31) |_| {
        var bt: u32 = @as(u32, 1) << fb;

        if (isNotZero(target_div & bt)) {
            div = fb;
            target_div &= ~(bt);

            if (isNotZero(target_div)) {
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

fn switchClockRate(self: *Self, base_clock: u32, target_rate: u32) bool {
    const divider: u32 = self.getClockDivider(base_clock, target_rate);

    while (isNotZero(self.registers.status & (StatusRegister.CmdInhibit | StatusRegister.DataInhibit))) {
        delayMillis(1);
    }

    const c1: u32 = self.registers.control[1] & ~ControlRegister.ClockEnable;

    self.registers.control[1] = c1;

    delayMillis(3);

    self.registers.control[1] = (c1 | divider) & ~@as(u32, 0xFFE0);

    delayMillis(3);

    self.registers.control[1] = c1 | ControlRegister.ClockEnable;

    delayMillis(3);

    return true;
}

fn setupClock(self: *Self) bool {
    self.registers.control2 = 0;

    const rate: u32 = self.emmc_clock_rate;

    var n = self.registers.control[1];
    n |= ControlRegister.ClockIntEnable;
    n |= self.getClockDivider(rate, SDClock.ID);
    n &= ~(@as(u32, 0xf) << 16);
    n |= (11 << 16);

    self.registers.control[1] = n;

    if (!waitRegister(&self.registers.control[1], ControlRegister.ClockStable, true, 2000)) {
        _ = printf("emmc: sd clock not stable\n");
        return false;
    }

    delayMillis(30);

    // Enable the clock.
    self.registers.control[1] |= 4;

    delayMillis(30);

    return true;
}

// Utility functions.
inline fn isNotZero(value: u32) bool {
    return value != 0;
}

inline fn isZero(value: u32) bool {
    return value == 0;
}

fn waitRegister(r: *volatile u32, mask: u32, set: bool, timeout: u32) bool {
    for (0..timeout) |_| {
        if (isNotZero(r.* & mask) == set) {
            return true;
        }
        delayMillis(1);
    }
    _ = printf("sdcard: wait register timeout\n");
    return false;
}

// Takes an Error value
fn errorMask(err: u32) u32 {
    const shift: u5 = @truncate(err + 16);
    return @as(u32, 1) << shift;
}
