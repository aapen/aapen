const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;

const peripheral_base: u64 = 0x3f000000; // RPi 3
//  const peripheral_base: u64 = 0xfe000000;   // RPi 4

extern fn spin_delay(cpu_cycles: u32) void;

// const GPIOPin = enum(u8) {
//   pin3 = 2,
//   pin5 = 3,
//   pin7 = 4,
//   pin11 = 17,
//   pin13 = 27,
//   pin15 = 22,
//   pin19 = 10,
//   pin21 = 9,
//   pin23 = 11,
//   pin29 = 5,
//   pin31 = 6,
//   pin33 = 13,
//   pin35 = 19,
//   pin37 = 26,
//   pin8 = 14,
//   pin10 = 15,
//   pin12 = 18,
//   pin16 = 23,
//   pin18 = 24,
//   pin22 = 25,
//   pin24 = 8,
//   pin26 = 7,
//   pin32 = 12,
//   pin36 = 16,
//   pin38 = 20,
//   pin40 = 21,
// };

//
// GPIO registers and their structures
// Note: this is incomplete... at the moment, it only contains enough
// to get a serial connection
const gpio_base = peripheral_base + 0x200000;

pub const GPIOFunctionSelect = enum(u3) {
    input = 0b000,
    output = 0b001,
    alt0 = 0b100,
    alt1 = 0b101,
    alt2 = 0b110,
    alt3 = 0b111,
    alt4 = 0b011,
    alt5 = 0b010,
};

const gpio_function_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x00),
    UniformRegister(u32).init(gpio_base + 0x04),
    UniformRegister(u32).init(gpio_base + 0x08),
    UniformRegister(u32).init(gpio_base + 0x0c),
    UniformRegister(u32).init(gpio_base + 0x10),
    UniformRegister(u32).init(gpio_base + 0x14),
};

const gpio_output_set_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x1c),
    UniformRegister(u32).init(gpio_base + 0x20),
};

const gpio_output_clear_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x28),
    UniformRegister(u32).init(gpio_base + 0x2c),
};

const gpio_level_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x34),
    UniformRegister(u32).init(gpio_base + 0x38),
};

const gpio_event_detect_status_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x40),
    UniformRegister(u32).init(gpio_base + 0x44),
};

const gpio_rising_edge_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x4c),
    UniformRegister(u32).init(gpio_base + 0x50),
};

const gpio_falling_edge_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x58),
    UniformRegister(u32).init(gpio_base + 0x5c),
};

const gpio_pin_high_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x64),
    UniformRegister(u32).init(gpio_base + 0x68),
};

const gpio_pin_low_detect_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x70),
    UniformRegister(u32).init(gpio_base + 0x74),
};

const gpio_pull_up_pull_down_enable_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x94),
};

const gpio_pull_up_pull_down_enable_clock_registers = [_]UniformRegister(u32){
    UniformRegister(u32).init(gpio_base + 0x98),
    UniformRegister(u32).init(gpio_base + 0x9c),
};

const GPIOPin = struct {
    const Self = @This();
    
    physical_id: u8,
    broadcom_id: u8,
    function_select_register_index: u8,
    function_select_register_shift: u5,
    data_register_index: u8,
    data_register_shift: u5,
    getset_mask: u32,

    fn define(physical_id: u8, broadcom_id: u8) Self {
        var fsel_bitstart: u5 = @truncate(@mod(broadcom_id * 3, 30));
        var fsel_register_index: u8 = broadcom_id / 10;
        var data_register_index: u8 = broadcom_id / 32;
        var data_register_shift: u5 = @truncate(@mod(broadcom_id, 32));
        var getset_mask: u32 = @as(u32, 1) << data_register_shift;

        return .{
                 .physical_id = physical_id,
                 .broadcom_id = broadcom_id,
                 .function_select_register_index = fsel_register_index,
                 .function_select_register_shift = fsel_bitstart,
                 .data_register_index = data_register_index,
                 .data_register_shift = data_register_shift,
                 .getset_mask = getset_mask,
                };
    }

    fn select_function(self: *const Self, fsel: GPIOFunctionSelect) void {
        var val = gpio_function_registers[self.function_select_register_index].read_raw();
        val &= ~(@as(u32, 7) << self.function_select_register_shift);
        val |= (@as(u32, @intFromEnum(fsel)) << self.function_select_register_shift);
        gpio_function_registers[self.function_select_register_index].write_raw(val);
    }

    fn enable(self: *const Self) void {
        gpio_pull_up_pull_down_enable_registers[0].write_raw(0);
        spin_delay(150);
        gpio_pull_up_pull_down_enable_clock_registers[self.data_register_index].write_raw(self.getset_mask);
        spin_delay(150);
        gpio_pull_up_pull_down_enable_registers[0].write_raw(0);
        gpio_pull_up_pull_down_enable_clock_registers[self.data_register_index].write_raw(0);
    }

    fn set(self: *const Self) void {
        gpio_output_set_registers[self.data_register_index].write_raw(self.getset_mask);
    }
    
    fn clear(self: *const Self) void {
        gpio_output_clear_registers[self.data_register_index].write_raw(self.getset_mask);
    }

    fn get(self: *const Self) bool {
        var levels = gpio_level_registers[self.data_register_index].read_raw();
        return (levels & self.getset_mask) != 0;
    }
};

pub const pins = struct {
    const Pin14 = GPIOPin.define(8, 14);
    const Pin15 = GPIOPin.define(10, 15);
};

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
    pins.Pin14.enable();
    pins.Pin15.enable();

    pins.Pin14.select_function(GPIOFunctionSelect.alt0);
    pins.Pin15.select_function(GPIOFunctionSelect.alt0);

    // gpio_function_select_1.modify(.{
    //     .fsel14 = .alt0,
    //     .fsel15 = .alt0,
    // });

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
