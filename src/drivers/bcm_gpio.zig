extern fn spinDelay(cpu_cycles: u32) void;

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

const Registers = extern struct {
    function_select: [6]u32,
    output_set: [2]u32,
    output_clear: [2]u32,
    level: [2]u32,
    event_detect_status: [2]u32,
    rising_edge_detect_enable: [2]u32,
    falling_edge_detect_enable: [2]u32,
    pin_high_detect_enable: [2]u32,
    pin_low_detect_enable: [2]u32,
    pull_up_pull_down_enable: [1]u32,
    pull_up_pull_down_enable_clock: [2]u32,
};

const Pin = struct {
    physical_id: u8,
    broadcom_id: u8,
    function_select_register_index: u8,
    function_select_register_shift: u5,
    data_register_index: u8,
    data_register_shift: u5,
    getset_mask: u32,
};

fn pin(physical_id: u8, broadcom_id: u8) Pin {
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

pub const Pins = [_]Pin{
    .{}, // +5v
    .{}, // GND
    pin(3, 2),
    pin(5, 3),
    pin(7, 4),
    pin(29, 5),
    pin(31, 6),
    pin(26, 7),
    pin(24, 8),
    pin(21, 9),
    pin(19, 10),
    pin(23, 11),
    pin(32, 12),
    pin(33, 13),
    pin(8, 14),
    pin(10, 15),
    pin(36, 16),
    pin(11, 17),
    pin(12, 18),
    pin(35, 19),
    pin(38, 20),
    pin(40, 21),
    pin(15, 22),
    pin(16, 23),
    pin(18, 24),
    pin(22, 25),
    pin(37, 26),
    pin(13, 27),
};

pub const BroadcomGpio2 = struct {
    registers: *volatile Registers = undefined,

    pub fn selectFunction(self: *const BroadcomGpio2, p: *Pin, fsel: FunctionSelect) void {
        var val = self.registers.function_select[p.function_select_register_index];
        val &= ~(@as(u32, 7) << p.function_select_register_shift);
        val |= (@as(u32, @intFromEnum(fsel)) << p.function_select_register_shift);
        self.registers.function_select[p.function_select_register_index] = val;
    }

    pub fn enable(self: *const BroadcomGpio2, p: *Pin) void {
        // clock in a zero for all pull up / pull down
        self.registers.pull_up_pull_down_enable[0] = 0;
        spinDelay(150);

        // enable PU/PD for this pin
        self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = p.getset_mask;
        spinDelay(150);

        // clock in a zero
        self.registers.pull_up_pull_down_enable[0] = 0;
        self.registers.pull_up_pull_down_enable_clock[p.data_register_index] = 0;
    }

    pub fn set(self: *const BroadcomGpio2, p: *Pin) void {
        self.registers.output_set[p.data_register_index] = p.getset_mask;
    }

    pub fn clear(self: *const BroadcomGpio2, p: *Pin) void {
        self.registers.output_clear[p.data_register_index] = p.getset_mask;
    }

    pub fn get(self: *const BroadcomGpio2, p: *Pin) bool {
        var levels = self.registers.level[p.data_register_index];
        return (levels & p.getset_mask) != 0;
    }
};

pub const BroadcomGpio = struct {
    const Self = @This();

    registers: *volatile Registers = undefined,
    pins: [28]Self.Pin = undefined,

    pub fn init(self: *BroadcomGpio, register_base: u64) void {
        self.registers = @ptrFromInt(register_base);

        self.pins[2] = Self.Pin.define(self, 3, 2);
        self.pins[3] = Self.Pin.define(self, 5, 3);
        self.pins[4] = Self.Pin.define(self, 7, 4);
        self.pins[5] = Self.Pin.define(self, 29, 5);
        self.pins[6] = Self.Pin.define(self, 31, 6);
        self.pins[7] = Self.Pin.define(self, 26, 7);
        self.pins[8] = Self.Pin.define(self, 24, 8);
        self.pins[9] = Self.Pin.define(self, 21, 9);
        self.pins[10] = Self.Pin.define(self, 19, 10);
        self.pins[11] = Self.Pin.define(self, 23, 11);
        self.pins[12] = Self.Pin.define(self, 32, 12);
        self.pins[13] = Self.Pin.define(self, 33, 13);
        self.pins[14] = Self.Pin.define(self, 8, 14);
        self.pins[15] = Self.Pin.define(self, 10, 15);
        self.pins[16] = Self.Pin.define(self, 36, 16);
        self.pins[17] = Self.Pin.define(self, 11, 17);
        self.pins[18] = Self.Pin.define(self, 12, 18);
        self.pins[19] = Self.Pin.define(self, 35, 19);
        self.pins[20] = Self.Pin.define(self, 38, 20);
        self.pins[21] = Self.Pin.define(self, 40, 21);
        self.pins[22] = Self.Pin.define(self, 15, 22);
        self.pins[23] = Self.Pin.define(self, 16, 23);
        self.pins[24] = Self.Pin.define(self, 18, 24);
        self.pins[25] = Self.Pin.define(self, 22, 25);
        self.pins[26] = Self.Pin.define(self, 37, 26);
        self.pins[27] = Self.Pin.define(self, 13, 27);
    }

    const Pin = struct {
        owner: *BroadcomGpio,
        physical_id: u8,
        broadcom_id: u8,
        function_select_register_index: u8,
        function_select_register_shift: u5,
        data_register_index: u8,
        data_register_shift: u5,
        getset_mask: u32,

        fn define(owner: *BroadcomGpio, physical_id: u8, broadcom_id: u8) Self.Pin {
            var fsel_bitstart: u5 = @truncate(@mod(broadcom_id * 3, 30));
            var fsel_register_index: u8 = broadcom_id / 10;
            var data_register_index: u8 = broadcom_id / 32;
            var data_register_shift: u5 = @truncate(@mod(broadcom_id, 32));
            var getset_mask: u32 = @as(u32, 1) << data_register_shift;

            return .{
                .owner = owner,
                .physical_id = physical_id,
                .broadcom_id = broadcom_id,
                .function_select_register_index = fsel_register_index,
                .function_select_register_shift = fsel_bitstart,
                .data_register_index = data_register_index,
                .data_register_shift = data_register_shift,
                .getset_mask = getset_mask,
            };
        }

        pub fn selectFunction(self: *const Self.Pin, fsel: FunctionSelect) void {
            var val = self.owner.registers.function_select[self.function_select_register_index];
            val &= ~(@as(u32, 7) << self.function_select_register_shift);
            val |= (@as(u32, @intFromEnum(fsel)) << self.function_select_register_shift);
            self.owner.registers.function_select[self.function_select_register_index] = val;
        }

        pub fn enable(self: *const Self.Pin) void {
            // clock in a zero for all pull up / pull down
            self.owner.registers.pull_up_pull_down_enable[0] = 0;
            spinDelay(150);

            // enable PU/PD for this pin
            self.owner.registers.pull_up_pull_down_enable_clock[self.data_register_index] = self.getset_mask;
            spinDelay(150);

            // clock in a zero
            self.owner.registers.pull_up_pull_down_enable[0] = 0;
            self.owner.registers.pull_up_pull_down_enable_clock[self.data_register_index] = 0;
        }

        pub fn set(self: *const Self.Pin) void {
            self.owner.registers.output_set[self.data_register_index] = self.getset_mask;
        }

        pub fn clear(self: *const Self.Pin) void {
            self.onwer.registers.output_clear[self.data_register_index] = self.getset_mask;
        }

        pub fn get(self: *const Self.Pin) bool {
            var levels = self.owner.registers.level[self.data_register_index];
            return (levels & self.getset_mask) != 0;
        }
    };
};
