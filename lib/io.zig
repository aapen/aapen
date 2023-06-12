const reg = @import("register.zig");
const UniformRegister = reg.UniformRegister;

const peripheral_base: u64 = 0x3f000000; // RPi 3
//  const peripheral_base: u64 = 0xfe000000;   // RPi 4

//
// GPIO registers and their structures
// Note: this is incomplete... at the moment, it only contains enough
// to get a serial connection
const gpio_base = peripheral_base + 0x200000;

pub const FunctionSelect = enum(u3) {
    input = 0b000,
    output = 0b001,
    alt0 = 0b100,
    alt1 = 0b101,
    alt2 = 0b110,
    alt3 = 0b111,
    alt4 = 0b011,
    alt5 = 0b010,
};

const gpio_function_select_0_layout = packed struct {
    fsel0: FunctionSelect,
    fsel1: FunctionSelect,
    fsel2: FunctionSelect,
    fsel3: FunctionSelect,
    fsel4: FunctionSelect,
    fsel5: FunctionSelect,
    fsel6: FunctionSelect,
    fsel7: FunctionSelect,
    fsel8: FunctionSelect,
    fsel9: FunctionSelect,
    _unused_reserved: u2,
};
const gpio_function_select_0 = UniformRegister(gpio_function_select_0_layout).init(gpio_base + 0x00);

const gpio_function_select_1_layout = packed struct {
    fsel10: FunctionSelect,
    fsel11: FunctionSelect,
    fsel12: FunctionSelect,
    fsel13: FunctionSelect,
    fsel14: FunctionSelect,
    fsel15: FunctionSelect,
    fsel16: FunctionSelect,
    fsel17: FunctionSelect,
    fsel18: FunctionSelect,
    fsel19: FunctionSelect,
    _unused_reserved: u2,
};
const gpio_function_select_1 = UniformRegister(gpio_function_select_1_layout).init(gpio_base + 0x04);

const gpio_function_select_2_layout = packed struct {
    fsel20: FunctionSelect,
    fsel21: FunctionSelect,
    fsel22: FunctionSelect,
    fsel23: FunctionSelect,
    fsel24: FunctionSelect,
    fsel25: FunctionSelect,
    fsel26: FunctionSelect,
    fsel27: FunctionSelect,
    fsel28: FunctionSelect,
    fsel29: FunctionSelect,
    _unused_reserved: u2,
};
const gpio_function_select_2 = UniformRegister(gpio_function_select_2_layout).init(gpio_base + 0x08);

const gpio_function_select_3_layout = packed struct {
    fsel30: FunctionSelect,
    fsel31: FunctionSelect,
    fsel32: FunctionSelect,
    fsel33: FunctionSelect,
    fsel34: FunctionSelect,
    fsel35: FunctionSelect,
    fsel36: FunctionSelect,
    fsel37: FunctionSelect,
    fsel38: FunctionSelect,
    fsel39: FunctionSelect,
    _unused_reserved: u2,
};
const gpio_function_select_3 = UniformRegister(gpio_function_select_3_layout).init(gpio_base + 0x0c);

const gpio_function_select_4_layout = packed struct {
    fsel40: FunctionSelect,
    fsel41: FunctionSelect,
    fsel42: FunctionSelect,
    fsel43: FunctionSelect,
    fsel44: FunctionSelect,
    fsel45: FunctionSelect,
    fsel46: FunctionSelect,
    fsel47: FunctionSelect,
    fsel48: FunctionSelect,
    fsel49: FunctionSelect,
    _unused_reserved: u2,
};
const gpio_function_select_4 = UniformRegister(gpio_function_select_4_layout).init(gpio_base + 0x10);

const gpio_function_select_5_layout = packed struct {
    fsel50: FunctionSelect,
    fsel51: FunctionSelect,
    fsel52: FunctionSelect,
    fsel53: FunctionSelect,
    _unused_reserved: u20,
};
const gpio_function_select_5 = UniformRegister(gpio_function_select_5_layout).init(gpio_base + 0x14);

const gpio_set_layout = packed struct {
    set: u32,
};
const gpio_set_0 = UniformRegister(gpio_set_layout).init(gpio_base + 0x1c);
const gpio_set_1 = UniformRegister(gpio_set_layout).init(gpio_base + 0x20);

const gpio_clear_layout = packed struct {
    clear: u32,
};
const gpio_clear_0 = UniformRegister(gpio_clear_layout).init(gpio_base + 0x28);
const gpio_clear_1 = UniformRegister(gpio_clear_layout).init(gpio_base + 0x2c);

//
// PL011 UART registers and their structures
//
const pl011_uart_base: u64 = peripheral_base + 0x201000;

const pl011_uart_dr_layout = packed struct {
    data: u8,
    framing_error: u1 = 0,
    parity_error: u1 = 0,
    break_error: u1 = 0,
    overrun_error: u1 = 0,
    _unused_reserved: u20 = 0,
};
const pl011_uart_dr = UniformRegister(pl011_uart_dr_layout).init(pl011_uart_base + 0x00);

const pl011_uart_fr_layout = packed struct {
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
const pl011_uart_fr = UniformRegister(pl011_uart_fr_layout).init(pl011_uart_base + 0x18);

const pl011_uart_ibrd_layout = packed struct {
    integer_baud_rate_divisor: u16,
    _unused_reserved: u16 = 0,
};
const pl011_uart_ibrd = UniformRegister(pl011_uart_ibrd_layout).init(pl011_uart_base + 0x24);

const pl011_uart_fbrd_layout = packed struct {
    fractional_baud_rate_divisor: u6,
    _unused_reserved: u26 = 0,
};
const pl011_uart_fbrd = UniformRegister(pl011_uart_fbrd_layout).init(pl011_uart_base + 0x28);

const pl011_uart_lcrh_layout = packed struct {
    send_break: u1 = 0,
    parity_enable: u1 = 0,
    even_parity_select: u1 = 0,
    two_stop_bit_select: u1 = 0,
    fifo_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    word_length: enum(u2) {
        eight_bits = 0b11,
        seven_bits = 0b10,
        six_bits = 0b01,
        five_bits = 0b00,
    } = .eight_bits,
    stick_parity_select: u1 = 0,
    _unused_reserved: u24 = 0,
};
const pl011_uart_lcrh = UniformRegister(pl011_uart_lcrh_layout).init(pl011_uart_base + 0x2c);

const pl011_uart_cr_layout = packed struct {
    uart_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    _unused_siren: u1 = 0,
    _unused_sirlp: u1 = 0,
    _unused_reserved: u3 = 0,
    loopback_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    transmit_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    receive_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    _unused_dtr: u1 = 0,
    request_to_send: u1 = 0,
    _unused_out1: u1 = 0,
    _unused_out2: u1 = 0,
    request_to_send_flow_control_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    clear_to_send_flow_control_enable: enum(u1) {
        disable = 0,
        enable = 1,
    } = .disable,
    _unused_reserved_2: u17 = 0,
};
const pl011_uart_cr = UniformRegister(pl011_uart_cr_layout).init(pl011_uart_base + 0x30);

const pl011_uart_ifls_layout = packed struct {
    transmit_interrupt_fifo_level_select: enum(u3) {
        one_eighth = 0b000,
        one_quarter = 0b001,
        one_half = 0b010,
        three_quarters = 0b011,
        seven_eighths = 0b100,
    } = .one_eighth,
    receive_interrupt_fifo_level_select: enum(u3) {
        one_eighth = 0b000,
        one_quarter = 0b001,
        one_half = 0b010,
        three_quarters = 0b011,
        seven_eighths = 0b100,
    } = .one_eighth,
    _unused_reserved: u26 = 0,
};
const pl011_uart_ifls = UniformRegister(pl011_uart_ifls_layout).init(pl011_uart_base + 0x34);

const pl011_uart_imsc_layout = packed struct {
    _unused_rimm: u1 = 0,
    clear_to_send_modem_interrupt_mask: u1 = 0,
    _unused_dcdmim: u1 = 0,
    _unused_dsrmim: u1 = 0,
    receive_interrupt_mask: u1 = 0,
    transmit_interrupt_mask: u1 = 0,
    receive_timeout_interrupt_mask: u1 = 0,
    framing_error_interrupt_mask: u1 = 0,
    parity_error_interrupt_mask: u1 = 0,
    break_error_interrupt_mask: u1 = 0,
    overrun_error_interrupt_mask: u1 = 0,
    _unused_reserved: u21,
};
const pl011_uart_imsc = UniformRegister(pl011_uart_imsc_layout).init(pl011_uart_base + 0x38);

const pl011_uart_ris_layout = packed struct {
    _unused_rirmis: u1 = 0,
    clear_to_send_modem_interrupt_status: u1 = 0,
    _unused_dcdrmis: u1 = 0,
    _unused_dsrrmis: u1 = 0,
    receive_interrupt_status: u1 = 0,
    transmit_interrupt_status: u1 = 0,
    receive_timeout_interrupt_status: u1 = 0,
    framing_error_interrupt_status: u1 = 0,
    parity_error_interrupt_status: u1 = 0,
    break_error_interrupt_status: u1 = 0,
    overrun_error_interrupt_status: u1 = 0,
    _unused_reserved: u20 = 0,
};
const pl011_uart_ris = UniformRegister(pl011_uart_ris_layout).init(pl011_uart_base + 0x3c);

const pl011_uart_mis_layout = packed struct {
    _unused_rimmis: u1 = 0,
    clear_to_send_masked_interrupt_status: u1 = 0,
    _unused_dcdmmis: u1 = 0,
    _unused_dsrmmis: u1 = 0,
    receive_masked_interrupt_status: u1 = 0,
    transmit_masked_interrupt_status: u1 = 0,
    receive_timeout_masked_interrupt_status: u1 = 0,
    framing_error_masked_interrupt_status: u1 = 0,
    parity_error_masked_interrupt_status: u1 = 0,
    break_error_masked_interrupt_status: u1 = 0,
    overrun_error_masked_interrupt_status: u1 = 0,
    _unused_reserved: u20 = 0,
};
const pl011_uart_mis = UniformRegister(pl011_uart_mis_layout).init(pl011_uart_base + 0x40);

const pl011_uart_icr_layout = packed struct {
    _unused_rimic: u1 = 0,
    clear_to_send_interrupt_clear: u1 = 0,
    _unused_dcdmic: u1 = 0,
    _unused_dsrmic: u1 = 0,
    receive_interrupt_clear: u1 = 0,
    transmit_interrupt_clear: u1 = 0,
    receive_timeout_interrupt_clear: u1 = 0,
    framing_error_interrupt_clear: u1 = 0,
    parity_error_interrupt_clear: u1 = 0,
    break_error_interrupt_clear: u1 = 0,
    overrun_error_interrupt_clear: u1 = 0,
    _unused_reserved: u20 = 0,
};
const pl011_uart_icr = UniformRegister(pl011_uart_icr_layout).init(pl011_uart_base + 0x44);

fn pl011_uart_is_write_byte_ready() bool {
    return (pl011_uart_fr.read().transmit_fifo_full == 0);
}

fn pl011_uart_is_read_byte_ready() bool {
    var receive_fifo_empty = pl011_uart_fr.read().receive_fifo_empty;
    return receive_fifo_empty == 0;
}

pub fn pl011_uart_blocking_write_byte(ch: u8) void {
    while (!pl011_uart_is_write_byte_ready()) {}

    pl011_uart_dr.write(.{ .data = ch });
}

pub fn pl011_uart_write_text(buffer: []const u8) void {
    for (buffer) |ch| {
        if (ch == '\n') {
            pl011_uart_blocking_write_byte('\r');
        }
        pl011_uart_blocking_write_byte(ch);
    }
}

pub fn pl011_uart_blocking_read_byte() u8 {
    while (!pl011_uart_is_read_byte_ready()) {}

    var rval = pl011_uart_dr.read();
    return rval.data;
}

pub fn pl011_uart_init() void {
    // Configure GPIO pins for serial I/O
    gpio_function_select_1.modify(.{
        .fsel14 = .alt0,
        .fsel15 = .alt0,
    });

    // Turn UART off while initializing
    pl011_uart_cr.write(.{ .uart_enable = .disable });

    // Flush the transmit FIFO
    pl011_uart_lcrh.write(.{ .fifo_enable = .disable });

    // Clear all pending interrupts
    pl011_uart_icr.write_raw(0x00);

    // From the PL011 Technical Reference Manual:
    //
    // The LCR_H, IBRD, and FBRD registers form the single 30-bit wide LCR Register that is
    // updated on a single write strobe generated by a LCR_H write. So, to internally update the
    // contents of IBRD or FBRD, a LCR_H write must always be performed at the end.
    //
    // Set the baud rate, 8N1 and FIFO enabled.
    pl011_uart_ibrd.write(.{ .integer_baud_rate_divisor = 0x03 });
    pl011_uart_fbrd.write(.{ .fractional_baud_rate_divisor = 0x10 });
    pl011_uart_lcrh.write(.{
        .word_length = .eight_bits,
        .fifo_enable = .enable,
    });

    // Set the receive and transmit FIFOs fill level at one-eighth
    pl011_uart_ifls.modify(.{
        .receive_interrupt_fifo_level_select = .one_eighth,
        .transmit_interrupt_fifo_level_select = .one_eighth,
    });

    // Enable receive and receive timeout interrupts
    pl011_uart_imsc.modify(.{
        .receive_interrupt_mask = 1,
        .receive_timeout_interrupt_mask = 1,
        .transmit_interrupt_mask = 1,
    });

    pl011_uart_cr.modify(.{
        .transmit_enable = .enable,
        .receive_enable = .enable,
    });

    // Turn the UART on
    pl011_uart_cr.modify(.{
        .uart_enable = .enable,
    });
}
