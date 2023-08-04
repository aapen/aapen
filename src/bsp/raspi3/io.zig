const std = @import("std");
const reg = @import("../mmio_register.zig");
const UniformRegister = reg.UniformRegister;
const interrupts = @import("interrupts.zig");
const ring = @import("../../ring.zig");
const cpu = @import("../../architecture.zig").cpu;
const peripheral_base = @import("memory_map.zig").peripheral_base;

extern fn spinDelay(cpu_cycles: u32) void;

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

    fn selectFunction(self: *const Self, fsel: GPIOFunctionSelect) void {
        var val = gpio_function_registers[self.function_select_register_index].read_raw();
        val &= ~(@as(u32, 7) << self.function_select_register_shift);
        val |= (@as(u32, @intFromEnum(fsel)) << self.function_select_register_shift);
        gpio_function_registers[self.function_select_register_index].write_raw(val);
    }

    fn enable(self: *const Self) void {
        gpio_pull_up_pull_down_enable_registers[0].write_raw(0);
        spinDelay(150);
        gpio_pull_up_pull_down_enable_clock_registers[self.data_register_index].write_raw(self.getset_mask);
        spinDelay(150);
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
    const Pin2 = GPIOPin.define(3, 2);
    const Pin3 = GPIOPin.define(5, 3);
    const Pin4 = GPIOPin.define(7, 4);
    const Pin5 = GPIOPin.define(29, 5);
    const Pin6 = GPIOPin.define(31, 6);
    const Pin7 = GPIOPin.define(26, 7);
    const Pin8 = GPIOPin.define(24, 8);
    const Pin9 = GPIOPin.define(21, 9);
    const Pin10 = GPIOPin.define(19, 10);
    const Pin11 = GPIOPin.define(23, 11);
    const Pin12 = GPIOPin.define(32, 12);
    const Pin13 = GPIOPin.define(33, 13);
    const Pin14 = GPIOPin.define(8, 14);
    const Pin15 = GPIOPin.define(10, 15);
    const Pin16 = GPIOPin.define(36, 16);
    const Pin17 = GPIOPin.define(11, 17);
    const Pin18 = GPIOPin.define(12, 18);
    const Pin19 = GPIOPin.define(35, 19);
    const Pin20 = GPIOPin.define(38, 20);
    const Pin21 = GPIOPin.define(40, 21);
    const Pin22 = GPIOPin.define(15, 22);
    const Pin23 = GPIOPin.define(16, 23);
    const Pin24 = GPIOPin.define(18, 24);
    const Pin25 = GPIOPin.define(22, 25);
    const Pin26 = GPIOPin.define(37, 26);
    const Pin27 = GPIOPin.define(13, 27);
};

//
// PL011 UART registers and their structures
//
const pl011_uart_base: u64 = peripheral_base + 0x201000;

const Pl011UartDRLayout = packed struct {
    data: u8,
    framing_error: u1 = 0,
    parity_error: u1 = 0,
    break_error: u1 = 0,
    overrun_error: u1 = 0,
    _unused_reserved: u20 = 0,
};
const pl011_uart_dr = UniformRegister(Pl011UartDRLayout).init(pl011_uart_base + 0x00);

const Pl011UartRSRECRLayout = packed struct {
    framing_error: u1 = 0,
    parity_error: u1 = 0,
    break_error: u1 = 0,
    overrun_error: u1 = 0,
    _unused_reserved: u28 = 0,
};
const pl011_uart_rsrecr = UniformRegister(Pl011UartRSRECRLayout).init(pl011_uart_base + 0x04);

const Pl011UartFRLayout = packed struct {
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
const pl011_uart_fr = UniformRegister(Pl011UartFRLayout).init(pl011_uart_base + 0x18);

const Pl011UartIBRDLayout = packed struct {
    integer_baud_rate_divisor: u16,
    _unused_reserved: u16 = 0,
};
const pl011_uart_ibrd = UniformRegister(Pl011UartIBRDLayout).init(pl011_uart_base + 0x24);

const Pl011UartFBRDLayout = packed struct {
    fractional_baud_rate_divisor: u6,
    _unused_reserved: u26 = 0,
};
const pl011_uart_fbrd = UniformRegister(Pl011UartFBRDLayout).init(pl011_uart_base + 0x28);

const EnableBitP = enum(u1) {
    disable = 0,
    enable = 1,
};

const Pl011UartLCRHLayout = packed struct {
    send_break: u1 = 0,
    parity_enable: u1 = 0,
    even_parity_select: u1 = 0,
    two_stop_bit_select: u1 = 0,
    fifo_enable: EnableBitP = .disable,
    word_length: enum(u2) {
        eight_bits = 0b11,
        seven_bits = 0b10,
        six_bits = 0b01,
        five_bits = 0b00,
    } = .eight_bits,
    stick_parity_select: u1 = 0,
    _unused_reserved: u24 = 0,
};
const pl011_uart_lcrh = UniformRegister(Pl011UartLCRHLayout).init(pl011_uart_base + 0x2c);

const Pl011UartCRLayout = packed struct {
    uart_enable: EnableBitP = .disable, // [0]
    _unused_siren: u1 = 0, // [1]
    _unused_sirlp: u1 = 0, // [2]
    _unused_reserved: u4 = 0, // [6:3]
    loopback_enable: EnableBitP = .disable, // [7]
    transmit_enable: EnableBitP = .disable, // [8]
    receive_enable: EnableBitP = .disable, // [9]
    _unused_dtr: u1 = 0, // [10]
    request_to_send: u1 = 0, // [11]
    _unused_out1: u1 = 0, // [12]
    _unused_out2: u1 = 0, // [13]
    request_to_send_flow_control_enable: EnableBitP = .disable, // [14]
    clear_to_send_flow_control_enable: EnableBitP = .disable, // [15]
    _unused_reserved_2: u16 = 0, // [16:31]
};
const pl011_uart_cr = UniformRegister(Pl011UartCRLayout).init(pl011_uart_base + 0x30);

const FifoLevelSelect = enum(u3) {
    one_eighth = 0b000,
    one_quarter = 0b001,
    one_half = 0b010,
    three_quarters = 0b011,
    seven_eighths = 0b100,
};

const Pl011UartIFLSLayout = packed struct {
    transmit_interrupt_fifo_level_select: FifoLevelSelect = .one_eighth,
    receive_interrupt_fifo_level_select: FifoLevelSelect = .one_eighth,
    _unused_reserved: u26 = 0,
};
const pl011_uart_ifls = UniformRegister(Pl011UartIFLSLayout).init(pl011_uart_base + 0x34);

const InterruptBit = enum(u1) {
    not_raised = 0,
    raised = 1,
};

const Pl011UartIMSCLayout = packed struct {
    _unused_rimm: u1 = 0,
    clear_to_send_modem_interrupt_mask: InterruptBit = .not_raised,
    _unused_dcdmim: u1 = 0,
    _unused_dsrmim: u1 = 0,
    receive_interrupt_mask: InterruptBit = .not_raised,
    transmit_interrupt_mask: InterruptBit = .not_raised,
    receive_timeout_interrupt_mask: InterruptBit = .not_raised,
    framing_error_interrupt_mask: InterruptBit = .not_raised,
    parity_error_interrupt_mask: InterruptBit = .not_raised,
    break_error_interrupt_mask: InterruptBit = .not_raised,
    overrun_error_interrupt_mask: InterruptBit = .not_raised,
    _unused_reserved: u21 = 0,
};
const pl011_uart_imsc = UniformRegister(Pl011UartIMSCLayout).init(pl011_uart_base + 0x38);

const Pl011UartRISLayout = packed struct {
    _unused_rirmis: u1 = 0,
    clear_to_send_modem_interrupt_status: InterruptBit = .not_raised,
    _unused_dcdrmis: u1 = 0,
    _unused_dsrrmis: u1 = 0,
    receive_interrupt_status: InterruptBit = .not_raised,
    transmit_interrupt_status: InterruptBit = .not_raised,
    receive_timeout_interrupt_status: InterruptBit = .not_raised,
    framing_error_interrupt_status: InterruptBit = .not_raised,
    parity_error_interrupt_status: InterruptBit = .not_raised,
    break_error_interrupt_status: InterruptBit = .not_raised,
    overrun_error_interrupt_status: InterruptBit = .not_raised,
    _unused_reserved: u21 = 0,
};
const pl011_uart_ris = UniformRegister(Pl011UartRISLayout).init(pl011_uart_base + 0x3c);

const Pl011UartMisLayout = packed struct {
    _unused_rimmis: u1 = 0, // [0]
    clear_to_send_masked_interrupt_status: InterruptBit = .not_raised, // [1]
    _unused_dcdmmis: u1 = 0, // [2]
    _unused_dsrmmis: u1 = 0, // [3]
    receive_masked_interrupt_status: InterruptBit = .not_raised, // [4]
    transmit_masked_interrupt_status: InterruptBit = .not_raised, // [5]
    receive_timeout_masked_interrupt_status: InterruptBit = .not_raised, // [6]
    framing_error_masked_interrupt_status: InterruptBit = .not_raised, // [7]
    parity_error_masked_interrupt_status: InterruptBit = .not_raised, // [8]
    break_error_masked_interrupt_status: InterruptBit = .not_raised, // [9]
    overrun_error_masked_interrupt_status: InterruptBit = .not_raised, // [10]
    _unused_reserved: u21 = 0,
};
const pl011_uart_mis = UniformRegister(Pl011UartMisLayout).init(pl011_uart_base + 0x40);

const Pl011UartICRLayout = packed struct {
    _unused_rimic: u1 = 0,
    clear_to_send_interrupt_clear: InterruptBit = .not_raised,
    _unused_dcdmic: u1 = 0,
    _unused_dsrmic: u1 = 0,
    receive_interrupt_clear: InterruptBit = .not_raised,
    transmit_interrupt_clear: InterruptBit = .not_raised,
    receive_timeout_interrupt_clear: InterruptBit = .not_raised,
    framing_error_interrupt_clear: InterruptBit = .not_raised,
    parity_error_interrupt_clear: InterruptBit = .not_raised,
    break_error_interrupt_clear: InterruptBit = .not_raised,
    overrun_error_interrupt_clear: InterruptBit = .not_raised,
    _unused_reserved: u21 = 0,
};
const pl011_uart_icr = UniformRegister(Pl011UartICRLayout).init(pl011_uart_base + 0x44);

//
// PL011 Interrupts
//
pub const Pl011Irqs = struct {
    // See BCM2837 ARM Peripherals, section 7.5
    // The UART irq is a "basic" irq which appears in the base register
    pub const uart_base_register_irq_bit: u64 = 1 << 19;

    // But for enabling/disabling we have to use the proper IRQ #
    pub const uart_irq: u64 = 1 << 57;
};

pub fn pl011IrqEnable() void {
    interrupts.irqEnable(Pl011Irqs.uart_irq);
}

pub fn pl011IrqDisable() void {
    interrupts.irqDisable(Pl011Irqs.uart_irq);
}

pub fn pl011IrqHandle() void {
    var interrupts_raised = pl011_uart_mis.read();

    if (interrupts_raised.receive_masked_interrupt_status == .raised) {
        var ch = pl011_uart_dr.read().data;
        read_buffer.enqueue(ch);
    }

    if (interrupts_raised.transmit_masked_interrupt_status == .raised) {
        var ch = write_buffer.dequeue();
        pl011_uart_dr.write(.{ .data = ch });

        if (write_buffer.empty()) {
            pl011_uart_imsc.modify(.{
                .transmit_interrupt_mask = .not_raised,
            });
        }
    }
}

// ----------------------------------------------------------------------
// Buffered IO - interrupt-driven with ring buffer
// ----------------------------------------------------------------------

var read_buffer = ring.Ring(u8).init();
var write_buffer = ring.Ring(u8).init();

pub fn stringSend(str: []const u8) void {
    // mask interrupts so we don't get interrupted in the middle of this function.
    cpu.irqDisable();
    defer cpu.irqEnable();

    // enable transmit interrupt (even if it already was)
    pl011_uart_imsc.modify(.{
        .transmit_interrupt_mask = .raised,
    });

    var rest = str;

    // if ready to send and no interrupt raised
    var interrupt_is_raised = pl011_uart_ris.read().transmit_interrupt_status == .raised;

    if (pl011WriteByteReady() and !interrupt_is_raised) {
        // take first ch from string, write it to data register
        // when this ch is done sending, will raise a UARTTXINTR
        var ch = str[0];
        rest = str[1..];
        pl011WriteByteBlocking(ch);
    }

    // enqueue rest of str, these will be send from the interrupt handler
    for (rest) |ch| {
        write_buffer.enqueue(ch);
    }
}

pub fn send(ch: u8) void {
    // mask interrupts so we don't get interrupted in the middle of this function.
    cpu.irqDisable();
    defer cpu.irqEnable();

    // if ready to send
    if (pl011WriteByteReady()) {
        // when this ch is done sending, will raise a UARTTXINTR
        pl011WriteByteBlocking(ch);
    } else {
        // enable transmit interrupt (even if it already was)
        pl011_uart_imsc.modify(.{
            .transmit_interrupt_mask = .raised,
        });
        // something is already sending, enqueue this for when it finishes
        write_buffer.enqueue(ch);
    }
}

pub fn receive() u8 {
    while (read_buffer.empty()) {
        // block
        cpu.wfi();
    }

    return read_buffer.dequeue();
}

// ----------------------------------------------------------------------
// Unbuffered IO - spins on status register
// ----------------------------------------------------------------------

fn pl011WriteByteReady() bool {
    return (pl011_uart_fr.read().transmit_fifo_full == 0);
}

fn pl011ReadByteReady() bool {
    var receive_fifo_empty = pl011_uart_fr.read().receive_fifo_empty;
    return receive_fifo_empty == 0;
}

pub fn pl011WriteByteBlocking(ch: u8) void {
    while (!pl011WriteByteReady()) {}

    pl011_uart_dr.write(.{ .data = ch });
}

pub fn pl011WriteText(buffer: []const u8) void {
    for (buffer) |ch| {
        pl011WriteByteBlocking(ch);
    }
}

pub fn pl011ReadByteBlocking() u8 {
    while (!pl011ReadByteReady()) {}

    var rval = pl011_uart_dr.read();
    return rval.data;
}

pub fn pl011Init() void {
    // Configure GPIO pins for serial I/O
    pins.Pin14.enable();
    pins.Pin15.enable();

    pins.Pin14.selectFunction(GPIOFunctionSelect.alt0);
    pins.Pin15.selectFunction(GPIOFunctionSelect.alt0);

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
    // Set the baud rate, 8N1 and FIFO disabled.
    //
    // Formula is 48,000,000 hz / (16 * 115200 baud) = 26.0417
    // IBRD = 26 = 0x1a
    // FBRD = ((0.417 * 64) + 0.5) = 27 = 0x1b
    pl011_uart_ibrd.write(.{ .integer_baud_rate_divisor = 0x1a });
    pl011_uart_fbrd.write(.{ .fractional_baud_rate_divisor = 0x1b });
    pl011_uart_lcrh.write(.{
        .word_length = .eight_bits,
        .fifo_enable = .disable,
    });

    // Enable receive interrupts. Transmit interrupts are enabled when data is written.
    pl011_uart_imsc.modify(.{
        .receive_interrupt_mask = .raised,
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

pub fn uartInit() void {
    pl011Init();
    pl011IrqEnable();
}

/// uart console
const UartWriter = std.io.Writer(u32, error{}, uartStringSend);
pub var uart_writer = UartWriter{ .context = 0 };

fn uartStringSend(_: u32, str: []const u8) !usize {
    stringSend(str);
    return str.len;
}
