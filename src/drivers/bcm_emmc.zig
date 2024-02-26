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
    try forth.defineStruct("emmc.sdcard", SDCard, .{
        .declarations = true,
    });
    try forth.defineNamespace(Self, .{
        .{ "enable", "emmc-enable" },
    });
}

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
    slot_int_status_version: u32,
};

pub const SdStatus = struct {
    const OK: u32 = 0x500;
    const Error: u32 = 0x501;
    const Timeout: u32 = 0x502;
};

const Frequency = struct {
    const FREQ_ID: u32 = 400000;
    const FREQ_NORMAL: u32 = 25000000;
    const FREQ_HIGH: u32 = 50000000;
    const FREQ_100: u32 = 100000000;
    const FREQ_208: u32 = 208000000;
};

const CmdFlag = struct {
    const TYPE_NORMAL: u32 = 0x0;
    const TYPE_SUSPEND: u32 = (1 << 22);
    const TYPE_RESUME: u32 = (2 << 22);
    const TYPE_ABORT: u32 = (3 << 22);
    const TYPE_MASK: u32 = (3 << 22);
    const ISDATA: u32 = (1 << 21);
    const IXCHK_EN: u32 = (1 << 20);
    const CRCCHK_EN: u32 = (1 << 19);

    const MULTI_BLOCK: u32 = (1 << 5);
    const DAT_DIR_HC: u32 = 0;
    const DAT_DIR_CH: u32 = (1 << 4);
    const AUTO_CMD_EN_NONE: u32 = 0;
    const AUTO_CMD_EN_CMD12: u32 = (1 << 2);
    const AUTO_CMD_EN_CMD23: u32 = (2 << 2);
    const BLKCNT_EN: u32 = (1 << 1);
    const DMA: u32 = 1;
};

const ErrorCode = struct {
    const CMD_TIMEOUT: u32 = 0;
    const CMD_CRC: u32 = 1;
    const CMD_END_BIT: u32 = 2;
    const CMD_INDEX: u32 = 3;
    const DATA_TIMEOUT: u32 = 4;
    const DATA_CRC: u32 = 5;
    const DATA_END_BIT: u32 = 6;
    const CURRENT_LIMIT: u32 = 7;
    const AUTO_CMD12: u32 = 8;
    const ADMA: u32 = 9;
    const TUNING: u32 = 10;
    const RSVD: u32 = 11;
};

const ErrorMask = struct {
    const SD_ERR_MASK_CMD_TIMEOUT: u32 = (1 << (16 + ErrorCode.CMD_TIMEOUT));
    const SD_ERR_MASK_CMD_CRC: u32 = (1 << (16 + ErrorCode.CMD_CRC));
    const SD_ERR_MASK_CMD_END_BIT: u32 = (1 << (16 + ErrorCode.CMD_END_BIT));
    const SD_ERR_MASK_CMD_INDEX: u32 = (1 << (16 + ErrorCode.CMD_INDEX));
    const SD_ERR_MASK_DATA_TIMEOUT: u32 = (1 << (16 + ErrorCode.CMD_TIMEOUT));
    const SD_ERR_MASK_DATA_CRC: u32 = (1 << (16 + ErrorCode.DATA_CRC));
    const SD_ERR_MASK_DATA_END_BIT: u32 = (1 << (16 + ErrorCode.DATA_END_BIT));
    const SD_ERR_MASK_CURRENT_LIMIT: u32 = (1 << (16 + ErrorCode.CURRENT_LIMIT));
    const SD_ERR_MASK_AUTO_CMD12: u32 = (1 << (16 + ErrorCode.AUTO_CMD12));
    const SD_ERR_MASK_ADMA: u32 = (1 << (16 + ErrorCode.ADMA));
    const SD_ERR_MASK_TUNING: u32 = (1 << (16 + ErrorCode.TUNING));
};

const Status = struct {
    const COMMAND_COMPLETE: u32 = 1;
    const TRANSFER_COMPLETE: u32 = (1 << 1);
    const BLOCK_GAP_EVENT: u32 = (1 << 2);
    const DMA_INTERRUPT: u32 = (1 << 3);
    const BUFFER_WRITE_READY: u32 = (1 << 4);
    const BUFFER_READ_READY: u32 = (1 << 5);
    const CARD_INSERTION: u32 = (1 << 6);
    const CARD_REMOVAL: u32 = (1 << 7);
    const CARD_INTERRUPT: u32 = (1 << 8);
};

const SD_DATA_READ: u32 = (CmdFlag.ISDATA | CmdFlag.DAT_DIR_CH);
const SD_DATA_WRITE: u32 = (CmdFlag.ISDATA | CmdFlag.DAT_DIR_HC);

//const SD_CMD_RESERVED(a): u32 = 0xffffffff;

const Version = struct {
    const V_UNKNOWN: u32 = 0;
    const V_1: u32 = 1;
    const V_1_1: u32 = 2;
    const V_2: u32 = 3;
    const V_3: u32 = 4;
    const V_4: u32 = 5;
};

const ResponseType = struct {
    const RT_NONE: u32 = 0;
    const RT_136: u32 = (1 << 16);
    const RT_48: u32 = (2 << 16);
    const RT_48B: u32 = (3 << 16);
    const RT_MASK: u32 = (3 << 16);
};

const Response = struct {
    const NONE: u32 = ResponseType.RT_NONE;
    const R1: u32 = (ResponseType.RT_48 | CmdFlag.CRCCHK_EN);
    const R1b: u32 = (ResponseType.RT_48B | CmdFlag.CRCCHK_EN);
    const R2: u32 = (ResponseType.RT_136 | CmdFlag.CRCCHK_EN);
    const R3: u32 = ResponseType.RT_48;
    const R4: u32 = ResponseType.RT_136;
    const R5: u32 = (ResponseType.RT_48 | CmdFlag.CRCCHK_EN);
    const R5b: u32 = (ResponseType.RT_48B | CmdFlag.CRCCHK_EN);
    const R6: u32 = (ResponseType.RT_48 | CmdFlag.CRCCHK_EN);
    const R7: u32 = (ResponseType.RT_48 | CmdFlag.CRCCHK_EN);
};

const CmdCode = struct {
    const GO_IDLE_STATE: u32 = 0x00000000;
    const ALL_SEND_CID: u32 = 0x02000000;
    const SEND_REL_ADDR: u32 = 0x03000000;
    const SET_DSR: u32 = 0x04000000;
    const SWITCH_FUNC: u32 = 0x06000000;
    const CARD_SELECT: u32 = 0x07000000;
    const SEND_IF_COND: u32 = 0x08000000;
    const SEND_CSD: u32 = 0x09000000;
    const SEND_CID: u32 = 0x0A000000;
    const VOLT_SWITCH: u32 = 0x0B000000;
    const STOP_TRANS: u32 = 0x0C000000;
    const SEND_STATUS: u32 = 0x0D000000;
    const GO_INACTIVE: u32 = 0x0F000000;
    const SET_BLOCKLEN: u32 = 0x10000000;
    const READ_SINGLE: u32 = 0x11000000;
    const READ_MULTI: u32 = 0x12000000;
    const SEND_TUNING: u32 = 0x13000000;
    const SPEED_CLASS: u32 = 0x14000000;
    const SET_BLOCKCNT: u32 = 0x17000000;
    const WRITE_SINGLE: u32 = 0x18000000;
    const WRITE_MULTI: u32 = 0x19000000;
    const PROGRAM_CSD: u32 = 0x1B000000;
    const SET_WRITE_PR: u32 = 0x1C000000;
    const CLR_WRITE_PR: u32 = 0x1D000000;
    const SND_WRITE_PR: u32 = 0x1E000000;
    const ERASE_WR_ST: u32 = 0x20000000;
    const ERASE_WR_END: u32 = 0x21000000;
    const ERASE: u32 = 0x26000000;
    const LOCK_UNLOCK: u32 = 0x2A000000;
    const APP_CMD: u32 = 0x37000000;
    const APP_CMD48: u32 = 0x37000000;
    const GEN_CMD: u32 = 0x38000000;
    const SET_BUS_WIDTH: u32 = 0x06000000;
    const SD_STATUS: u32 = 0x0D000000;
    const SEND_NUM_WRBL: u32 = 0x16000000;
    const SEND_NUM_ERS: u32 = 0x17000000;
    const SD_SENDOPCOND: u32 = 0x29000000;
    const SET_CLR_DET: u32 = 0x2A000000;
    const SEND_SCR: u32 = 0x33000000;
};

// This the info we keep for each command: The code that we send, the kind of response
// the cmd will return, does the command do rca and how long should we wait after issuing
// the command.
const Cmd = struct {
    code: u32,
    //res_type: u32,
    //rca: bool,
    response_type: u32,
    needs_app: bool,
    delay: u32,

    inline fn init(code: u32, response_type: u32, needs_app: bool, delay: u32) Cmd {
        return .{
            .code = code,
            .response_type = response_type,
            .needs_app = needs_app,
            .delay = delay,
        };
    }
};

const INVALID_CMD = Cmd.init(0xffffff, Response.NONE, false, 0);

const GO_IDLE_STATE = Cmd.init(CmdCode.GO_IDLE_STATE, Response.NONE, false, 0);
const ALL_SEND_CID = Cmd.init(CmdCode.ALL_SEND_CID, Response.R2I, false, 0);
const SEND_REL_ADDR = Cmd.init(CmdCode.SEND_REL_ADDR, Response.R6, false, 2000);
const SET_DSR = Cmd.init(CmdCode.SET_DSR, Response.NONE, false, 0);
const SWITCH_FUNC = Cmd.init(CmdCode.SWITCH_FUNC, Response.R1, false, 0);
const CARD_SELECT = Cmd.init(CmdCode.CARD_SELECT, Response.R1B, false, 2000);
const SEND_IF_COND = Cmd.init(CmdCode.SEND_IF_COND, Response.R7, false, 100);
const SEND_CSD = Cmd.init(CmdCode.SEND_CSD, Response.R2S, false, 0);
const SEND_CID = Cmd.init(CmdCode.SEND_CID, Response.R1I, false, 0);
const VOLT_SWITCH = Cmd.init(CmdCode.VOLT_SWITCH, Response.R1, false, 0);
const STOP_TRANS = Cmd.init(CmdCode.STOP_TRANS, Response.R1, false, 0);
const SEND_STATUS = Cmd.init(CmdCode.SEND_STATUS, Response.R1, false, 0);
const GO_INACTIVE = Cmd.init(CmdCode.GO_INACTIVE, Response.R1, false, 0);
const SET_BLOCKLEN = Cmd.init(CmdCode.SET_BLOCKLEN, Response.R1, false, 0);
const READ_SINGLE = Cmd.init(CmdCode.READ_SINGLE, Response.R1, false, 0);
const READ_MULTI = Cmd.init(CmdCode.READ_MULTI, Response.R1, false, 0);
const SEND_TUNING = Cmd.init(CmdCode.SEND_TUNING, Response.R1, false, 0);
const SPEED_CLASS = Cmd.init(CmdCode.SPEED_CLASS, Response.R1, false, 0);
const SET_BLOCKCNT = Cmd.init(CmdCode.SET_BLOCKCNT, Response.R1, false, 0);
const WRITE_SINGLE = Cmd.init(CmdCode.WRITE_SINGLE, Response.R1, false, 0);
const WRITE_MULTI = Cmd.init(CmdCode.WRITE_MULTI, Response.R1, false, 0);
const PROGRAM_CSD = Cmd.init(CmdCode.PROGRAM_CSD, Response.R1, false, 0);
const SET_WRITE_PR = Cmd.init(CmdCode.SET_WRITE_PR, Response.R1, false, 0);
const CLR_WRITE_PR = Cmd.init(CmdCode.CLR_WRITE_PR, Response.R1, false, 0);
const SND_WRITE_PR = Cmd.init(CmdCode.SND_WRITE_PR, Response.R1, false, 0);
const ERASE_WR_ST = Cmd.init(CmdCode.ERASE_WR_ST, Response.R1, false, 0);
const ERASE_WR_END = Cmd.init(CmdCode.ERASE_WR_END, Response.R1, false, 0);
const ERASE = Cmd.init(CmdCode.ERASE, Response.R1, false, 0);
const LOCK_UNLOCK = Cmd.init(CmdCode.LOCK_UNLOCK, Response.R1, false, 100);
const APP_CMD = Cmd.init(CmdCode.APP_CMD, Response.R1, false, 2000);
const APP_CMD48 = Cmd.init(CmdCode.APP_CMD48, Response.R1, false, 0);
const GEN_CMD = Cmd.init(CmdCode.GEN_CMD, Response.R1, false, 0);
const SET_BUS_WIDTH = Cmd.init(CmdCode.SET_BUS_WIDTH, Response.R1, true, 0);
const SD_STATUS = Cmd.init(CmdCode.SD_STATUS, Response.R1, true, 0);
const SEND_NUM_WRBL = Cmd.init(CmdCode.SEND_NUM_WRBL, Response.R1, true, 0);
const SEND_NUM_ERS = Cmd.init(CmdCode.SEND_NUM_ERS, Response.R1, true, 0);
const SD_SENDOPCOND = Cmd.init(CmdCode.SD_SENDOPCOND, Response.R1, true, 1000);
const SET_CLR_DET = Cmd.init(CmdCode.SET_CLR_DET, Response.R1, true, 0);
const SEND_SCR = Cmd.init(CmdCode.SEND_SCR, Response.R1, true, 0);

// Information about the SD Card.
const SDCard = struct {
    capacity: u64,
    cid: [4]u32,
    csd: [2]u32,
    scr: [2]u32,
    ocr: u32,
    hv: u32,
    support: u32,
    format: u32,
    block_size: u32,
    transfer_blocks: u32 = 0,
    card_type: u8,
    uhsi: u8,
    init: u8,
    absent: u8,

    rca: u32,
    cardState: u32,
    status: u32,

    last_cmd: *const Cmd,
    last_arg: u32,
    last_response: [2]u32,
    last_error: u32,
    last_interrupt: u32,
    last_success: bool,
};

fn dataReadyWait(self: *Self) SdStatus {
    return self.statusWaitForClear(StatusMask.DataInhibit);
}

fn cmdReadyWait(self: *Self) SdStatus {
    return self.statusWaitForClear(StatusMask.CmdInhibit);
}

// Wait for the status bits reflected in mask to clear.
inline fn statusWaitForClear(self: *Self, mask: u32) SdStatus {
    for (0..50000) |_| {
        if (!bitsAreSet(self.emmc_status, mask)) {
            return SdStatus.OK;
        } else if (bitsAreSet(self.emmc_interrupt, mask)) {
            return SdStatus.Error;
        }
        time.delayMillis(1);
    }
    return SdStatus.Timeout;
}
// command flags
//
//  const CmdNeedApp        : u32 = 0x80000000;
//  const CmdRspns48        : u32 = 0x00020000;
//  const CmdErrorsMask     : u32 = 0xfff9c004;
//  const CmdRcaMask        : u32 = 0xffff0000;
//
//  // Commands

// STATUS register settings
const StatusMask = struct {
    const ReadAvailable: u32 = 0x00000800;
    const DataInhibit: u32 = 0x00000002;
    const CmdInhibit: u32 = 0x00000001;
    const AppCmd: u32 = 0x00000020;
};

// INTERRUPT register settings
const InterruptMask = struct {
    const DataTimeout: u32 = 0x00100000;
    const CmdTimeout: u32 = 0x00010000;
    const ReadRdy: u32 = 0x00000020;
    const CmdDone: u32 = 0x00000001;
    const ErrorMask: u32 = 0x017e8000;
};

// CONTROL register settings
const ControlValue = struct {
    const C0_SpiModeEn: u32 = 0x00100000;
    const C0_HctlHsEn: u32 = 0x00000004;
    const C0_HctlDwitdh: u32 = 0x00000002;
    const C1_ResetData: u32 = 0x04000000;
    const C1_ResetCmd: u32 = 0x02000000;
    const C1_ResetHost: u32 = 0x01000000;
    const C1_TounitDis: u32 = 0x000F0000;
    const C1_TounitMax: u32 = 0x000E0000;
    const C1_ClockGensel: u32 = 0x00000020;
    const C1_ClockEnable: u32 = 0x00000004;
    const C1_ClockStable: u32 = 0x00000002;
    const C1_ClockIntlen: u32 = 0x00000001;

    const C1_ResetAll = C1_ResetData | C1_ResetCmd | C1_ResetHost;
};

// SLOTISR_VER values
const HostValue = struct {
    const HOST_SPEC_NUM: u32 = 0x00ff0000;
    const HOST_SPEC_NUM_SHIFT: u32 = 16;
    const HOST_SPEC_V3: u32 = 2;
    const HOST_SPEC_V2: u32 = 1;
    const HOST_SPEC_V1: u32 = 0;
};
//
//  // SCR flags
//  const  ScrValue = struct {
//      const SCR_SD_BUS_WIDTH_4 :u32 = 0x00000400;
//      const SCR_SUPP_SET_BLKCNT:u32 = 0x02000000;
//      const SCR_SUPP_CCS       :u32 = 0x00000001;
//  };
//
//  const AcmValue = struct {
//      const ACMD41_VOLTAGE     :u32 = 0x00ff8000;
//      const ACMD41_CMD_COMPLETE:u32 = 0x80000000;
//      const ACMD41_CMD_CCS     :u32 = 0x40000000;
//      const ACMD41_ARG_HC      :u32 = 0x51ff8000;
//  };
//
//
// SD Clock Frequencies (in Hz)

// SD_CLOCK_ID seems to be the lowest common denominator,
// used to determine what the card can do.
const ClockFrequency = struct {
    const SD_CLOCK_ID: u32 = 400000;
    const SD_CLOCK_NORMAL: u32 = 25000000;
    const SD_CLOCK_HIGH: u32 = 50000000;
    const SD_CLOCK_100: u32 = 100000000;
    const SD_CLOCK_208: u32 = 208000000;
};

pub fn init(allocator: Allocator, register_base: u64, gpio: *GPIO, interrupt_controller: *InterruptController, pclock_controller: *PeripheralClockController) !*Self {
    const self = try allocator.create(Self);

    const emmc_clock_rate: u32 = try pclock_controller.clockRateCurrent(CLOCK_EMMC);

    self.* = .{
        .registers = @ptrFromInt(register_base),
        .interrupt_controller = interrupt_controller,
        .gpio = gpio,
        .emmc_clock_rate = emmc_clock_rate,
        .sdcard = undefined,
    };
    return self;
}

inline fn bitsAreSet(value: u32, mask: u32) bool {
    const masked = value & mask;
    return masked != 0;
}

inline fn u32Swap(value: u32) u32 {
    var bytes = std.mem.asBytes(&value);
    var temp: [4]u8 = undefined;
    temp[3] = bytes[0];
    temp[2] = bytes[1];
    temp[1] = bytes[2];
    temp[0] = bytes[3];
    const p_result = std.mem.bytesAsValue(u32, &temp);
    return p_result.*;
}

const CMD_SEND_IF_COND: u32 = 0x08020000;

pub fn enable(self: *Self) bool {
    self.gpio.enable(2);
    self.gpio.enable(3);

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

    self.sdcard.scr[0] = 0;
    self.sdcard.scr[1] = 0;
    self.sdcard.rca = 0;
    self.sdcard.ocr = 0;
    self.sdcard.hv = self.host_version_get();

    var success: bool = false;
    for (0..10) |_| {
        success = self.card_reset();

        if (success) {
            break;
        }

        time.delayMillis(100);
        _ = printf("EMMC_WARN: Failed to reset card, trying again...\n");
    }

    if (!success) {
        _ = printf("Failed to reset!\n");
        return false;
    }

    _ = printf("setting freq\n");
    if (!self.sd_clk(400000)) {
        _ = printf("Failed to set clock!\n");
        return false;
    }
    _ = printf("setting freq Done\n");

    self.registers.int_enable = 0;
    self.registers.int_flags = 0xffffffff;
    self.registers.int_mask = 0xffffffff;

    const CMD_GO_IDLE: u32 = 0x00000000;
    if (!self.sd_cmd(CMD_GO_IDLE, 0)) {
        return false;
    }

    _ = printf("sent idle ok!\n");
    //const CMD_SEND_CID: u32 = 0x02010000;
    //const CMD_SEND_CID: u32 = 0x01000000;
    //const CMD_SEND_CID: u32 = 0x02010000;
    _ = printf("\nsending if cond!\n");
    if (!self.sd_cmd(CMD_SEND_IF_COND, 0x000001AA)) {
        _ = printf("if cond failed resetting!\n");
        _ = self.card_reset();
        _ = printf("done with reset!\n");
    } else {
        self.dump_response();
    }

    const CMD_SEND_OP_COND = 0x29020000;
    const ACMD41_ARG_HC: u32 = 0x51ff8000;

    const CMD_APP_CMD: u32 = 0x37000000;

    for (0..6) |_| {
        time.delayMillis(1);
        _ = self.sd_cmd(CMD_APP_CMD, 0);
        _ = self.sd_cmd(CMD_SEND_OP_COND, ACMD41_ARG_HC);
    }

    time.delayMillis(1000);
    return true;
}

fn maskWaitSet(p_reg: *volatile u32, mask: u32, timeout: u32) bool {
    for (0..timeout) |_| {
        if (bitsAreSet(p_reg.*, mask)) {
            return true;
        }
        time.delayMillis(1);
    }

    return false;
}

fn maskWaitClear(p_reg: *volatile u32, mask: u32, timeout: u32) bool {
    kernelMessage("mask wait clr enter  ");
    for (0..timeout) |_| {
        kernelMessage("checking... ");
        if (!bitsAreSet(p_reg.*, mask)) {
            kernelMessage("true! ");
            return true;
        }
        time.delayMillis(1);
    }

    kernelMessage("false! ");
    return false;
}

fn card_reset(self: *Self) bool {
    _ = printf("emmc: Card resetting...\n");
    //*EMMC_CONTROL0 = 0; *EMMC_CONTROL1 |= C1_SRST_HC;
    //
    const C1_SRST_HC: u32 = 0x01000000;
    self.registers.control[0] = 0;
    self.registers.control[1] = C1_SRST_HC;

    //cnt=10000; do{wait_msec(10);} while( (*EMMC_CONTROL1 & C1_SRST_HC) && cnt-- );
    //time.delayMillis(10);
    var count: u32 = 0;
    while (count < 10000) {
        if ((self.registers.control[1] & C1_SRST_HC) == 0) {
            break;
        }
        _ = printf("emmc: Card reset loop...\n");
        count += 1;
        time.delayMillis(1);
    }

    if (count >= 10000) {
        _ = printf("emmc: card timed out resetting...\n");
        return false;
    }
    _ = printf("emmc: card reset OK...\n");

    //*EMMC_CONTROL1 |= C1_CLK_INTLEN | C1_TOUNIT_MAX;

    const C1_TOUNIT_MAX: u32 = 0x000e0000;
    const C1_CLK_INTLEN: u32 = 0x00000001;

    self.registers.control[1] |= C1_CLK_INTLEN | C1_TOUNIT_MAX;
    time.delayMillis(1);
    _ = printf("emmc: card reset done...\n");
    return true;
}

fn wait_for_ready(self: *Self) bool {
    //int cnt = 100000;
    //while((*EMMC_STATUS & (SR_CMD_INHIBIT|SR_DAT_INHIBIT)) && cnt--) wait_msec(1);
    //const SR_READ_AVAILABLE   :u32 = 0x00000800;
    const SR_DAT_INHIBIT: u32 = 0x00000002;
    const SR_CMD_INHIBIT: u32 = 0x00000001;
    //const SR_APP_CMD          :u32 = 0x00000020;

    var count: u32 = 100000;
    while (count > 0) {
        if (self.registers.status & (SR_CMD_INHIBIT | SR_DAT_INHIBIT) == 0) {
            break;
        }
        count -= 1;
        _ = printf("emmc: ready pause\n");
        time.delayMillis(1);
    }
    if (count == 0) {
        _ = printf("emmc: timeout waiting for ready\n");
        return false;
    }
    return true;
}

fn wait_for_stable(self: *Self) bool {
    //    cnt=10000; while(!(*EMMC_CONTROL1 & C1_CLK_STABLE) && cnt--) wait_msec(10);

    _ = printf("emmc: waiting for stable\n");
    const C1_CLK_STABLE: u32 = 0x00000002;

    var count: u32 = 100000;
    while (count > 0) {
        if ((self.registers.control[1] & C1_CLK_STABLE) != 0) {
            break;
        }
        count -= 1;
        _ = printf("emmc: stable pause\n");
        time.delayMillis(1);
    }
    if (count == 0) {
        _ = printf("emmc: timeout waiting for stable\n");
        return false;
    }
    return true;
}

fn host_version_get(self: *Self) u32 {
    const HOST_SPEC_NUM: u32 = 0x00ff0000;
    const HOST_SPEC_NUM_SHIFT: u32 = 16;

    //sd_hv = (*EMMC_SLOTISR_VER & HOST_SPEC_NUM) >> HOST_SPEC_NUM_SHIFT;

    const hv = (self.registers.slot_int_status_version & HOST_SPEC_NUM) >> HOST_SPEC_NUM_SHIFT;

    _ = printf("emmc: host version get: %d\n", hv);
    return hv;
}

fn wait_for_interrupt(self: *Self, mask: u32) bool {
    //unsigned int r, m=mask | INT_ERROR_MASK;
    const INT_ERROR_MASK: u32 = 0x00202000;
    const INT_DATA_TIMEOUT: u32 = 0x00100000;
    const INT_CMD_TIMEOUT: u32 = 0x00010000;

    const m: u32 = mask | INT_ERROR_MASK;

    // int cnt = 1000000; while(!(*EMMC_INTERRUPT & m) && cnt--) wait_msec(1);

    //_ = printf("emmc wait int: mask: %x int_flags %x\n", mask, self.registers.int_flags);

    var count: u32 = 100000;
    while (count > 0) {
        if ((self.registers.int_flags & m) != 0) {
            break;
        }
        count -= 1;
        //_ = printf("emmc: interrupt pause\n");
        time.delayMillis(1);
    }
    const r: u32 = self.registers.int_flags;
    _ = printf("emmc: int flags: %x\n", self.registers.int_flags);

    if (count == 0) {
        _ = printf("emmc: timeout waiting for interrupt\n");
        self.registers.int_flags = r;
        return false;
    } else if ((r & INT_CMD_TIMEOUT) != 0) {
        self.registers.int_flags = r;
        _ = printf("emmc: interrupt cmd timeout\n");
        return false;
    } else if ((r & INT_DATA_TIMEOUT) != 0) {
        self.registers.int_flags = r;
        _ = printf("emmc: interrupt data timeout\n");
        return false;
    } else if ((r & INT_ERROR_MASK) != 0) {
        self.registers.int_flags = r;
        _ = printf("emmc: interrupt error\n");
        return false;
    }
    return true;
}

fn dump_response(self: *Self) void {
    _ = printf("emmc: responses %x %x %x %x\n", self.registers.response[0], self.registers.response[1], self.registers.response[2], self.registers.response[3]);
}

fn sd_cmd(self: *Self, code: u32, arg: u32) bool {
    const CMD_NEED_APP: u32 = 0x80000000;

    if ((code & CMD_NEED_APP) != 0) {
        _ = printf("emmc: WARNING CMD NEED APP\n");
    }

    //var r: u32 =0;

    //    if(code&CMD_NEED_APP) {
    //        r=sd_cmd(CMD_APP_CMD|(sd_rca?CMD_RSPNS_48:0),sd_rca);
    //        if(sd_rca && !r) { uart_puts("ERROR: failed to send SD APP command\n"); sd_err=SD_ERROR;return 0;}
    //        code &= ~CMD_NEED_APP;
    //    }

    //    if(sd_status(SR_CMD_INHIBIT)) { uart_puts("ERROR: EMMC busy\n"); sd_err= SD_TIMEOUT;return 0;}
    if (!self.wait_for_ready()) {
        _ = printf("emmc: sd cmd ready timeout\n");
        return false;
    }

    _ = printf("emmc: sending command %x with arg %x\n", code, arg);

    //    *EMMC_INTERRUPT=*EMMC_INTERRUPT; *EMMC_ARG1=arg; *EMMC_CMDTM=code;
    self.registers.int_flags = self.registers.int_flags;
    _ = printf("starting int flags: %x\n", self.registers.int_flags);
    self.registers.arg1 = arg;
    self.registers.cmd_xfer_mode = code;

    //    if(code==CMD_SEND_OP_COND) wait_msec(1000); else
    if (code == CMD_SEND_IF_COND) {
        time.delayMillis(100);
    }
    //    if(code==CMD_SEND_IF_COND || code==CMD_APP_CMD) wait_msec(100);
    //time.delayMillis(100);

    //    if((r=sd_int(INT_CMD_DONE)))
    //    {uart_puts("ERROR: failed to send EMMC command\n");sd_err=r;return 0;}
    const INT_CMD_DONE: u32 = 0x00000001;

    const result = self.wait_for_interrupt(INT_CMD_DONE);
    if (!result) {
        _ = printf("emmc: failed to send cmd %x with arg %x\n", code, arg);
        return false;
    }

    _ = self.wait_for_ready();

    return true;

    //    r=*EMMC_RESP0;
    //    if(code==CMD_GO_IDLE || code==CMD_APP_CMD) return 0; else
    //    if(code==(CMD_APP_CMD|CMD_RSPNS_48)) return r&SR_APP_CMD; else
    //    if(code==CMD_SEND_OP_COND) return r; else
    //    if(code==CMD_SEND_IF_COND) return r==arg? SD_OK : SD_ERROR; else
    //    if(code==CMD_ALL_SEND_CID) {r|=*EMMC_RESP3; r|=*EMMC_RESP2; r|=*EMMC_RESP1; return r; } else
    //    if(code==CMD_SEND_REL_ADDR) {
    //        sd_err=(((r&0x1fff))|((r&0x2000)<<6)|((r&0x4000)<<8)|((r&0x8000)<<8))&CMD_ERRORS_MASK;
    //        return r&CMD_RCA_MASK;
    //    }
    //    return r&CMD_ERRORS_MASK;
    //    // make gcc happy
    //    return 0;
}

fn sd_clk(self: *Self, f: u32) bool {
    //unsigned int d,c=41666666/f,x,s=32,h=0;

    //var d: u32 = 0;
    var c: u32 = 41666666 / f;
    var s: u32 = 32;
    //var h: u32 = 0;

    // while((*EMMC_STATUS & (SR_CMD_INHIBIT|SR_DAT_INHIBIT)) && cnt--) wait_msec(1);
    //
    if (!self.wait_for_ready()) {
        _ = printf("emmc: sd_clk: timeout waiting for ready\n");
        return false;
    }

    //*EMMC_CONTROL1 &= ~C1_CLK_EN; wait_msec(10);
    const C1_CLK_EN: u32 = 0x00000004;
    self.registers.control[1] &= ~C1_CLK_EN;
    time.delayMillis(1);

    //    x=c-1; if(!x) s=0; else {
    //        if(!(x & 0xffff0000u)) { x <<= 16; s -= 16; }
    //        if(!(x & 0xff000000u)) { x <<= 8;  s -= 8; }
    //        if(!(x & 0xf0000000u)) { x <<= 4;  s -= 4; }
    //        if(!(x & 0xc0000000u)) { x <<= 2;  s -= 2; }
    //        if(!(x & 0x80000000u)) { x <<= 1;  s -= 1; }
    //        if(s>0) s--;
    //        if(s>7) s=7;
    //    }

    var x: u32 = c - 1;
    if (x == 0) {
        s = 0;
    } else {
        if ((x & 0xffff0000) == 0) {
            x = x << 16;
            s -= 16;
        }
        if ((x & 0xff000000) == 0) {
            x = x << 8;
            s -= 8;
        }
        if ((x & 0xf0000000) == 0) {
            x = x << 4;
            s -= 4;
        }
        if ((x & 0xc0000000) == 0) {
            x = x << 2;
            s -= 2;
        }
        if ((x & 0x80000000) == 0) {
            x = x << 1;
            s -= 1;
        }
        if (s > 0) {
            s -= 1;
        }
        if (s > 7) {
            s = 7;
        }
    }

    //    if(sd_hv>HOST_SPEC_V2) d=c; else d=(1<<s);
    var d: u32 = 0;

    if (self.sdcard.hv > 1) {
        d = c;
    } else {
        d = @as(u32, 1) << @as(u5, @intCast(s));
    }

    //    if(d<=2) {d=2;s=0;}
    if (d < 2) {
        d = 2;
        s = 0;
    }

    // uart_puts("sd_clk divisor ");uart_hex(d);uart_puts(", shift ");uart_hex(s);uart_puts("\n");
    _ = printf("emmc: divisor: %d\n", d);
    _ = printf("emmc: shift: %d\n", s);

    //
    //    if(sd_hv>HOST_SPEC_V2) h=(d&0x300)>>2;
    var h: u32 = 0;
    if (self.sdcard.hv > 1) {
        h = (d & 0x300) >> 2;
    }

    //    d=(((d&0x0ff)<<8)|h);
    d = ((d & 0x0ff) << 8) | h;

    //    *EMMC_CONTROL1=(*EMMC_CONTROL1&0xffff003f)|d; wait_msec(10);
    self.registers.control[1] |= d;
    time.delayMillis(1);

    //    *EMMC_CONTROL1 |= C1_CLK_EN; wait_msec(10);
    self.registers.control[1] |= C1_CLK_EN;
    //time.delayMillis(10);

    return self.wait_for_stable();

    //    cnt=10000; while(!(*EMMC_CONTROL1 & C1_CLK_STABLE) && cnt--) wait_msec(10);
    //    if(cnt<=0) {
    //        uart_puts("ERROR: failed to get stable clock\n");
    //        return SD_ERROR;
    //    }
    //    return SD_OK;
    // return true;
}

fn qqqcard_reset(self: *Self) bool {
    self.registers.control[1] = ControlValue.C1_ResetHost;
    _ = printf("emmc: Card resetting...\n");

    _ = printf("emmc: Waiting for resetall reg to clear\n");
    if (!maskWaitClear(&self.registers.control[1], ControlValue.C1_ResetAll, 2000)) {
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

    time.delayMillis(203);
    //timer_sleep(203);

    self.sdcard.transfer_blocks = 0;
    self.sdcard.last_cmd = &INVALID_CMD;
    self.sdcard.last_success = false;
    self.sdcard.block_size = 0;

    if (!self.cmdIssue(&GO_IDLE_STATE, 0)) {
        _ = printf("EMMC_ERR: NO GO_IDLE RESPONSE\n");
        return false;
    }

    //var v2_card = check_v2_card();

    //TBD
    //if (!check_usable_card()) {
    //    return false;
    //}

    //if (!check_ocr()) {
    //    return false;
    //}

    // Assume this is ok for now. TBD
    //
    //if (!check_sdhc_support(v2_card)) {
    //    return false;
    //}

    _ = printf("Setting freq\n");
    if (!self.clockSetRate(ClockFrequency.SD_CLOCK_NORMAL)) {
        _ = printf("EMMC_ERR: clock rate fail\n");
    }
    _ = printf("Done Setting freq\n");

    time.delayMillis(10);

    //if (!check_rca()) {
    //    return false;
    //}

    //if (!select_card()) {
    //    return false;
    //}

    //if (!set_scr()) {
    //    return false;
    // }

    //enable all interrupts
    self.registers.int_flags = 0xFFFFFFFF;

    _ = printf("EMMC_DEBUG: Card reset!\n");

    return true;
}

fn resetSend(self: *Self) bool {
    //self.registers.control[1] |= EMMC_CTRL1_RESET_CMD;
    self.registers.control[1] |= ControlValue.C1_ResetCmd;

    for (0..10000) |_| {
        if (!bitsAreSet(self.registers.control[1], ControlValue.C1_ResetCmd)) {
            return true;
        }

        time.delayMillis(1);
        //timer_sleep(1);
    }

    _ = printf("EMMC_ERR: Command line failed to reset properly: %x\n", self.registers.control[1]);

    return false;
}

pub fn clockComputeDiv(self: *Self, target_rate: u32) u32 {
    var divisor: u32 = self.emmc_clock_rate / target_rate;

    // Round down if we have an exact division.
    if ((self.emmc_clock_rate % target_rate) > 0) {
        divisor += 1;
    }

    // Divisor must be even.
    if ((divisor % 2) == 1) {
        divisor += 1;
    }
    return divisor;
}

pub fn clockSetRate(self: *Self, target_rate: u32) bool {
    var div: u32 = self.clockComputeDiv(target_rate);

    while (bitsAreSet(self.registers.status, StatusMask.CmdInhibit | StatusMask.DataInhibit)) {
        time.delayMillis(1);
    }

    const c1: u32 = self.registers.control[1] & ~ControlValue.C1_ClockEnable;

    self.registers.control[1] = c1;

    time.delayMillis(3);

    var reg_div: u32 = (c1 | div) & (~@as(u32, 0xFFE0));
    self.registers.control[1] = reg_div;

    time.delayMillis(3);

    self.registers.control[1] = c1 | ControlValue.C1_ClockEnable;

    time.delayMillis(3);

    return true;
}

pub fn emmc_setup_clock(self: *Self) bool {
    self.registers.control2 = 0;

    var n: u32 = self.registers.control[1];
    n |= ControlValue.C1_ClockEnable;
    n |= self.clockComputeDiv(ClockFrequency.SD_CLOCK_ID);
    _ = printf("clock div: %d\n", self.clockComputeDiv(ClockFrequency.SD_CLOCK_ID));
    var mask: u32 = 0xf << 16;
    mask = ~mask;
    n &= mask;
    n |= (11 << 16);

    self.registers.control[1] = n;

    //if (!maskWaitSet(&self.registers.control[1], ControlValue.C1_ClockStable, 2000)) {
    //    _ = printf("EMMC_ERR: SD CLOCK NOT STABLE\n");
    //    return false;
    //}
    time.delayMillis(1000); // TBD assume it works.

    time.delayMillis(30);

    //enabling the clock
    self.registers.control[1] |= 4;

    time.delayMillis(30);

    return true;
}

fn cmdIssue(self: *Self, cmd: *const Cmd, arg: u32) bool {
    self.registers.arg1 = arg;
    self.registers.cmd_xfer_mode = cmd.code;

    time.delayMillis(10);

    var times: u32 = 0;

    while (times < cmd.delay) {
        const reg: u32 = self.registers.int_flags;

        if ((reg & 0x8001) != 0) {
            break;
        }

        time.delayMillis(1);
        times += 1;
    }

    if (times >= cmd.delay) {
        //just doing a warn for this because sometimes it's ok.
        _ = printf("EMMC_WARN: emmc_issue_command timed out\n");
        self.sdcard.last_success = false;
        return false;
    }

    const intr_val = self.registers.int_flags;

    self.registers.int_flags = 0xFFFF0001;

    if ((intr_val & 0xFFFF0001) != 1) {
        _ = printf("EMMC_DEBUG: Error waiting for command interrupt complete: %d\n", cmd.code);

        //set_last_error(intr_val);
        self.sdcard.last_error = intr_val & 0xffff0000;
        self.sdcard.last_interrupt = intr_val;

        _ = printf("EMMC_DEBUG: IRQFLAGS: %X - %X - %X\n", self.registers.int_flags, self.registers.status, intr_val);

        self.sdcard.last_success = false;
        return false;
    }
    return true;
}

// fn cmdIssue(self: *Self, cmd: *const Cmd, arg: u32, delay: u32) bool {
//     time.delayMillis(delay);
//
//     self.sdcard.last_cmd = cmd;
//
//     if (self.sdcard.transfer_blocks > 0xFFFF) {
//         _ = printf("EMMC_ERR: transferBlocks too large: %d\n", self.sdcard.transfer_blocks);
//         return false;
//     }
//
//     //EMMC->block_size_count = device.block_size | (device.transfer_blocks << 16);
//     if (self.sdcard.block_size == 0) {
//         self.registers.block_size_count = self.sdcard.transfer_blocks << 16;
//     } else {
//         self.registers.block_size_count = self.sdcard.block_size;
//     }
//
//     self.registers.arg1 = arg;
//     self.registers.cmd_xfer_mode = cmd.code;
//
//     time.delayMillis(10);
//
//     var times: u32 = 0;
//
//     while (times < delay) {
//         const reg: u32 = self.registers.int_flags;
//
//         if ((reg & 0x8001) != 0) {
//             break;
//         }
//
//         time.delayMillis(delay);
//         times += 1;
//     }
//
//     if (times >= delay) {
//         //just doing a warn for this because sometimes it's ok.
//         _ = printf("EMMC_WARN: emmc_issue_command timed out\n");
//         self.sdcard.last_success = false;
//         return false;
//     }
//
//     const intr_val = self.registers.int_flags;
//
//     self.registers.int_flags = 0xFFFF0001;
//
//     if ((intr_val & 0xFFFF0001) != 1) {
//         _ = printf("EMMC_DEBUG: Error waiting for command interrupt complete: %d\n", cmd.code);
//
//         //set_last_error(intr_val);
//         self.sdcard.last_error = intr_val & 0xffff0000;
//         self.sdcard.last_interrupt = intr_val;
//
//         _ = printf("EMMC_DEBUG: IRQFLAGS: %X - %X - %X\n", self.registers.int_flags, self.registers.status, intr_val);
//
//         self.sdcard.last_success = false;
//         return false;
//     }
//
//     switch (cmd.response_type) {
//         Response.RT_48, Response.RT_48B => self.sdcard.last_response[0] = self.registers.response[0],
//
//         Response.RT_136 => {
//             self.sdcard.last_response[0] = self.registers.response[0];
//             self.sdcard.last_response[1] = self.registers.response[1];
//             self.sdcard.last_response[2] = self.registers.response[2];
//             self.sdcard.last_response[3] = self.registers.response[3];
//         },
//     }
//
//     //if (cmd.is_data) {
//     //    do_data_transfer(cmd);
//     //}
//
//     if (cmd.response_type == Response.RT_48Busy || cmd.is_data) {
//         maskWaitSet(&self.registers.int_flags, 0x8002, 2000);
//         intr_val = self.registers.int_flags;
//
//         self.registers.int_flags = 0xFFFF0002;
//
//         if ((intr_val & 0xFFFF0002) != 2 and (intr_val & 0xFFFF0002) != 0x100002) {
//             self.sdcard.last_error = intr_val & 0xffff0000;
//             self.sdcard.last_interrupt = intr_val;
//             return false;
//         }
//
//         self.registers.int_flags = 0xFFFF0002;
//     }
//
//     self.sdcard.last_success = true;
//
//     return true;
// }
//
// pub fn cmdSend(self: *Self, cmd: *const Cmd, arg: u32) bool {
//     //If the app flag is set, should use emmc_app_command instead.
//     if (cmd.needs_app) {
//         var rca_arg = self.sdcard.rca;
//         if (rca_arg != 0) {
//             rca_arg = rca_arg << 16;
//         }
//         if (!self.cmdIssue(&APP_CMD, rca_arg, APP_CMD.delay)) {
//             return false;
//         }
//     }
//
//     return self.cmdIssue(cmd, arg, cmd.delay);
// }
//
// // fn check_v2_card(self: *Self) bool {
// //     if (!emmc_command( CommandType.CTSendIfCond, 0x1AA, 200)) {
// //         if (self.last_error == 0) {
// //             //timeout.
// //             _ = printf("EMMC_ERR: SEND_IF_COND Timeout\n");
// //         } else if (self.last_error & (1 << 16)) {
// //             //timeout command error
// //             if (!reset_command()) {
// //                 return false;
// //             }
// //
// //             self.int_flags = sd_error_mask(SDError.SDECommandTimeout);
// //             _ = printf("EMMC_ERR: SEND_IF_COND CMD TIMEOUT\n");
// //         } else {
// //             _ = printf("EMMC_ERR: Failure sending SEND_IF_COND\n");
// //             return false;
// //         }
// //     } else {
// //         if ((self.last_response[0] & 0xFFF) != 0x1AA) {
// //             _ = printf("EMMC_ERR: Unusable SD Card: %X\n", self.last_response[0]);
// //             return false;
// //         }
// //
// //         return true;
// //     }
// // }
//
// //  fn check_usable_card(self: *Self) bool {
// //      if (!cmdSend( SendOpCondCmd, 0)) {
// //          if (self.last_error == 0) {
// //              //timeout.
// //              _ = printf("EMMC_ERR: CTIOSetOpCond Timeout\n");
// //          } else if (self.last_error & (1 << 16)) {
// //              //timeout command error
// //              //this is a normal expected error and calling the reset command will fix it.
// //              if (!resetSend()) {
// //                  return false;
// //              }
// //
// //              self.int_flags = sd_error_mask(SDError.SDECommandTimeout);
// //          } else {
// //              _ = printf("EMMC_ERR: SDIO Card not supported\n");
// //              return false;
// //          }
// //      }
// //
// //      return true;
// //  }
// ////
// //  fn check_ocr(self: *Self) bool {
// //      const passed = self.emmc_app_command(CTOcrCheck, 0, 2000);
// //
// //      if(! passed) {
// //          _ = printf("EMMC_WARN: OCR CHECK TRY FAILED\n");
// //          return false;
// //      }
// //
// //      self.ocr = (device.last_response[0] >> 8 & 0xFFFF);
// //      return passed;
// //  }
//
// fn select_card(self: *Self) bool {
//     if (!cmdSend(Cmd.CTSelectCard, self.rca << 16)) {
//         _ = printf("EMMC_ERR: Failed to select card\n");
//         return false;
//     }
//
//     _ = printf("EMMC_DEBUG: Selected Card\n");
//
//     const status: u32 = (self.sd_card.last_response[0] >> 9) & 0xF;
//
//     if ((status != 3) and (status != 4)) {
//         _ = printf("EMMC_ERR: Invalid Status: %d\n", status);
//         return false;
//     }
//
//     _ = printf("EMMC_DEBUG: Status: %d\n", status);
//
//     return true;
// }
//
// fn check_rca(self: *Self) bool {
//     if (!cmdSend(SEND_CID, 0)) {
//         _ = printf("EMMC_ERR: Failed to send CID\n");
//
//         return false;
//     }
//
//     _ = printf("EMMC_DEBUG: CARD ID: %X.%X.%X.%X\n", self.sdcard.last_response[0], self.sd_card.last_response[1], self.sd_card.last_response[2], self.sd_card.last_response[3]);
//
//     if (!cmdSend(SEND_REL_ADDR, 0)) {
//         _ = printf("EMMC_ERR: Failed to send Relative Addr\n");
//
//         return false;
//     }
//
//     self.sd_card.rca = (self.sd_card.last_response[0] >> 16) & 0xFFFF;
//
//     _ = printf("EMMC_DEBUG: RCA: %X\n", self.sd_card.rca);
//
//     _ = printf("EMMC_DEBUG: CRC_ERR: %d\n", (self.sd_card.last_response[0] >> 15) & 1);
//     _ = printf("EMMC_DEBUG: CMD_ERR: %d\n", (self.sd_card.last_response[0] >> 14) & 1);
//     _ = printf("EMMC_DEBUG: GEN_ERR: %d\n", (self.sd_card.last_response[0] >> 13) & 1);
//     _ = printf("EMMC_DEBUG: STS_ERR: %d\n", (self.sd_card.last_response[0] >> 9) & 1);
//     _ = printf("EMMC_DEBUG: READY  : %d\n", (self.sd_card.last_response[0] >> 8) & 1);
//
//     if (!((self.sd_card.last_response[0] >> 8) & 1)) {
//         _ = printf("EMMC_ERR: Failed to read RCA\n");
//         return false;
//     }
//
//     return true;
// }
//
// fn set_scr(self: *Self) bool {
//     if (self.cmdSend(SET_BLOCKLEN, 512)) {
//         _ = printf("EMMC_ERR: Failed to set block len\n");
//         return false;
//     }
//
//     var bsc: u32 = self.sdcard.block_size;
//     bsc &= ~0xFFF; //mask off bottom bits
//     bsc |= 0x200; //set bottom bits to 512
//     self.sdcard.block_size = bsc;
//
//     self.buffer = &self.scr.scr[0];
//     self.sdcard.block_size = 8;
//     self.transfer_blocks = 1;
//
//     if (!self.cmdIssue(SEND_SCR, 0, 30000)) {
//         _ = printf("EMMC_ERR: Failed to send SCR\n");
//         return false;
//     }
//
//     _ = printf("EMMC_DEBUG: GOT SRC: SCR0: %X SCR1: %X BWID: %X\n", self.scr.scr[0], self.scr.scr[1], self.scr.bus_widths);
//
//     self.sdcard.block_size = 512;
//
//     var scr0: u32 = u32Swap(self.scr.scr[0]);
//     self.scr.version = 0xFFFFFFFF;
//     var spec: u32 = (scr0 >> (56 - 32)) & 0xf;
//     var spec3: u32 = (scr0 >> (47 - 32)) & 0x1;
//     var spec4: u32 = (scr0 >> (42 - 32)) & 0x1;
//
//     if (spec == 0) {
//         self.scr.version = 1;
//     } else if (spec == 1) {
//         self.scr.version = 11;
//     } else if (spec == 2) {
//         if (spec3 == 0) {
//             self.scr.version = 2;
//         } else if (spec3 == 1) {
//             if (spec4 == 0) {
//                 self.scr.version = 3;
//             }
//             if (spec4 == 1) {
//                 self.scr.version = 4;
//             }
//         }
//     }
//
//     _ = printf("EMMC_DEBUG: SCR Version: %d\n", self.scr.version);
//
//     return true;
// }

registers: *volatile Registers,
interrupt_controller: *InterruptController,
gpio: *GPIO,
emmc_clock_rate: u32 = 0,
hostVersion: u32 = 0,
debug: u32 = 0,
sdcard: SDCard,
