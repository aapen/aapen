const std = @import("std");

const root = @import("root");
const GPIO = root.HAL.GPIO;

const Forth = @import("../forty/forth.zig").Forth;

const Self = @This();

pub fn defineModule(forth: *Forth) !void {
    _ = forth;
}

extern fn spinDelay(cpu_cycles: u32) void;

const DataRegister = packed struct {
    data: u8,
    framing_error: u1 = 0,
    parity_error: u1 = 0,
    break_error: u1 = 0,
    overrun_error: u1 = 0,
    _unused_reserved: u20 = 0,
};

const ReceiveStatusErrorClearRegister = packed struct {
    framing_error: u1 = 0,
    parity_error: u1 = 0,
    break_error: u1 = 0,
    overrun_error: u1 = 0,
    _unused_reserved: u28 = 0,
};

const FlagsRegister = packed struct {
    clear_to_send: u1 = 0,
    _unused_dsr: u1 = 0,
    _unused_dcd: u1 = 0,
    busy: u1 = 0,
    receive_fifo_empty: u1 = 0,
    transmit_fifo_full: u1 = 0,
    receive_fifo_full: u1 = 0,
    transmit_fifo_empty: u1 = 0,
    _unused_ri: u1 = 0,
    _unused_reserved: u23 = 0,
};

const IntegerBaudRateRegister = packed struct {
    integer_baud_rate_divisor: u16,
    _unused_reserved: u16 = 0,
};

const FractionalBaudRateRegister = packed struct {
    fractional_baud_rate_divisor: u6,
    _unused_reserved: u26 = 0,
};

const EnableBitP = struct {
    pub const disable: u1 = 0;
    pub const enable: u1 = 0;
};

const WordLength = struct {
    pub const eight_bits: u2 = 0b11;
    pub const seven_bits: u2 = 0b10;
    pub const six_bits: u2 = 0b01;
    pub const five_bits: u2 = 0b00;
};

const LineControlRegister = packed struct {
    send_break: u1 = 0,
    parity_enable: u1 = 0,
    even_parity_select: u1 = 0,
    two_stop_bit_select: u1 = 0,
    fifo_enable: u1 = EnableBitP.disable,
    word_length: u2 = WordLength.eight_bits,
    stick_parity_select: u1 = 0,
    _unused_reserved: u24 = 0,
};

const ControlRegister = packed struct {
    uart_enable: u1 = EnableBitP.disable, // [0]
    _unused_siren: u1 = 0, // [1]
    _unused_sirlp: u1 = 0, // [2]
    _unused_reserved: u4 = 0, // [6:3]
    loopback_enable: u1 = EnableBitP.disable, // [7]
    transmit_enable: u1 = EnableBitP.disable, // [8]
    receive_enable: u1 = EnableBitP.disable, // [9]
    _unused_dtr: u1 = 0, // [10]
    request_to_send: u1 = 0, // [11]
    _unused_out1: u1 = 0, // [12]
    _unused_out2: u1 = 0, // [13]
    request_to_send_flow_control_enable: u1 = EnableBitP.disable, // [14]
    clear_to_send_flow_control_enable: u1 = EnableBitP.disable, // [15]
    _unused_reserved_2: u16 = 0, // [16:31]
};

const FifoLevelSelect = struct {
    pub const one_eighth: u3 = 0b000;
    pub const one_quarter: u3 = 0b001;
    pub const one_half: u3 = 0b010;
    pub const three_quarters: u3 = 0b011;
    pub const seven_eighths: u3 = 0b100;
};

const InterruptFifoLevelSelectRegister = packed struct {
    transmit_interrupt_fifo_level_select: u3 = FifoLevelSelect.one_eighth,
    receive_interrupt_fifo_level_select: u3 = FifoLevelSelect.one_eighth,
    _unused_reserved: u26 = 0,
};

const InterruptBit = struct {
    pub const not_raised: u1 = 0;
    pub const raised: u1 = 1;
};

const InterruptMaskSetClearRegister = packed struct {
    _unused_rimm: u1 = 0,
    clear_to_send_modem_interrupt_mask: u1 = InterruptBit.not_raised,
    _unused_dcdmim: u1 = 0,
    _unused_dsrmim: u1 = 0,
    receive_interrupt_mask: u1 = InterruptBit.not_raised,
    transmit_interrupt_mask: u1 = InterruptBit.not_raised,
    receive_timeout_interrupt_mask: u1 = InterruptBit.not_raised,
    framing_error_interrupt_mask: u1 = InterruptBit.not_raised,
    parity_error_interrupt_mask: u1 = InterruptBit.not_raised,
    break_error_interrupt_mask: u1 = InterruptBit.not_raised,
    overrun_error_interrupt_mask: u1 = InterruptBit.not_raised,
    _unused_reserved: u21 = 0,
};

const RawInterruptStatusRegister = packed struct {
    _unused_rirmis: u1 = 0,
    clear_to_send_modem_interrupt_status: u1 = InterruptBit.not_raised,
    _unused_dcdrmis: u1 = 0,
    _unused_dsrrmis: u1 = 0,
    receive_interrupt_status: u1 = InterruptBit.not_raised,
    transmit_interrupt_status: u1 = InterruptBit.not_raised,
    receive_timeout_interrupt_status: u1 = InterruptBit.not_raised,
    framing_error_interrupt_status: u1 = InterruptBit.not_raised,
    parity_error_interrupt_status: u1 = InterruptBit.not_raised,
    break_error_interrupt_status: u1 = InterruptBit.not_raised,
    overrun_error_interrupt_status: u1 = InterruptBit.not_raised,
    _unused_reserved: u21 = 0,
};

const MaskedInterruptStatusRegister = packed struct {
    _unused_rimmis: u1 = 0, // [0]
    clear_to_send_masked_interrupt_status: u1 = InterruptBit.not_raised, // [1]
    _unused_dcdmmis: u1 = 0, // [2]
    _unused_dsrmmis: u1 = 0, // [3]
    receive_masked_interrupt_status: u1 = InterruptBit.not_raised, // [4]
    transmit_masked_interrupt_status: u1 = InterruptBit.not_raised, // [5]
    receive_timeout_masked_interrupt_status: u1 = InterruptBit.not_raised, // [6]
    framing_error_masked_interrupt_status: u1 = InterruptBit.not_raised, // [7]
    parity_error_masked_interrupt_status: u1 = InterruptBit.not_raised, // [8]
    break_error_masked_interrupt_status: u1 = InterruptBit.not_raised, // [9]
    overrun_error_masked_interrupt_status: u1 = InterruptBit.not_raised, // [10]
    _unused_reserved: u21 = 0,
};

const InterruptClearRegister = packed struct {
    _unused_rimic: u1 = 0,
    clear_to_send_interrupt_clear: u1 = InterruptBit.not_raised,
    _unused_dcdmic: u1 = 0,
    _unused_dsrmic: u1 = 0,
    receive_interrupt_clear: u1 = InterruptBit.not_raised,
    transmit_interrupt_clear: u1 = InterruptBit.not_raised,
    receive_timeout_interrupt_clear: u1 = InterruptBit.not_raised,
    framing_error_interrupt_clear: u1 = InterruptBit.not_raised,
    parity_error_interrupt_clear: u1 = InterruptBit.not_raised,
    break_error_interrupt_clear: u1 = InterruptBit.not_raised,
    overrun_error_interrupt_clear: u1 = InterruptBit.not_raised,
    _unused_reserved: u21 = 0,
};

const Registers = extern struct {
    data: DataRegister, // 0x00
    rsrecr: ReceiveStatusErrorClearRegister, // 0x04
    _reserved_0: [4]u32, // 0x08 - 0x14
    flags: FlagsRegister, // 0x18
    _reserved_1: u32 = 0, //0x1c
    _unused_0: u32 = 0, //0x20
    ibaud_rate_divisor: IntegerBaudRateRegister, // 0x24
    fbaud_rate_divisor: FractionalBaudRateRegister, // 0x28
    line_control: LineControlRegister, // 0x2c
    control: ControlRegister, // 0x30
    interrupt_fifo_level_select: InterruptFifoLevelSelectRegister, //0x34
    interrupt_mask_set_clear: InterruptMaskSetClearRegister, // 0x38
    raw_interrupt_status: RawInterruptStatusRegister, // 0x3c
    masked_interrupt_status: MaskedInterruptStatusRegister, //0x40
    interrupt_clear: InterruptClearRegister, //0x44
};

registers: *volatile Registers,
gpio: *GPIO,

pub fn init(register_base: u64, gpio: *GPIO) Self {
    return .{
        .registers = @ptrFromInt(register_base),
        .gpio = gpio,
    };
}

pub fn initializeUart(self: *Self) void {
    // Configure GPIO pins for serial I/O
    self.gpio.enable(14);
    self.gpio.enable(15);

    self.gpio.selectFunction(14, GPIO.FunctionSelect.Alt0);
    self.gpio.selectFunction(15, GPIO.FunctionSelect.Alt0);

    // Turn UART off while initializing
    self.registers.control.uart_enable = EnableBitP.disable;

    // Flush the transmit FIFO
    self.registers.line_control.fifo_enable = EnableBitP.disable;

    // Clear all pending interrupts
    const clear_all: u32 = 0x00;
    self.registers.interrupt_clear = @bitCast(clear_all);

    // From the PL011 Technical Reference Manual:
    //
    // The LCR_H, IBRD, and FBRD registers form the single 30-bit wide LCR Register that is
    // updated on a single write strobe generated by a LCR_H write. So, to internally update the
    // contents of IBRD or FBRD, a LCR_H write must always be performed at the end.
    //
    // Set the baud rate, 8N1 and FIFO disabled.
    //
    // Formula is 48,000,000 hz / (16 * 115200 baud) = 26.0417
    // IBRD = 26 = 0x1a
    // FBRD = ((0.417 * 64) + 0.5) = 27 = 0x1b
    self.registers.ibaud_rate_divisor.integer_baud_rate_divisor = 0x1a;
    self.registers.fbaud_rate_divisor.fractional_baud_rate_divisor = 0x1b;
    self.registers.line_control = .{
        .word_length = WordLength.eight_bits,
        .fifo_enable = EnableBitP.disable,
    };

    self.registers.interrupt_mask_set_clear = .{
        .receive_interrupt_mask = InterruptBit.not_raised,
        .transmit_interrupt_mask = InterruptBit.not_raised,
    };
    self.registers.control = .{
        .transmit_enable = EnableBitP.enable,
        .receive_enable = EnableBitP.enable,
    };

    // Turn the UART on
    self.registers.control.uart_enable = EnableBitP.enable;
}

pub fn getc(self: *Self) u8 {
    while (self.registers.flags.receive_fifo_empty != 0) {}
    return self.registers.data.data;
}

pub fn putc(self: *Self, ch: u8) void {
    while (self.registers.flags.transmit_fifo_full != 0) {}
    self.registers.data.data = ch;
}

pub fn hasc(self: *Self) bool {
    return self.registers.flags.receive_fifo_empty == 0;
}
