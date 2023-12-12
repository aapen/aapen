const std = @import("std");

const synchronize = @import("../../synchronize.zig");
const Spinlock = synchronize.Spinlock;

const local_timer = @import("../arm_local_timer.zig");
const Clock = local_timer.Clock;

const usb = @import("../../usb.zig");
pub const DeviceAddress = usb.DeviceAddress;
pub const TransactionStage = usb.TransactionStage;
pub const EndpointDirection = usb.EndpointDirection;
pub const EndpointNumber = usb.EndpointNumber;
pub const EndpointType = usb.EndpointType;
pub const PacketSize = usb.PacketSize;
pub const PID = usb.PID2;
pub const UsbSpeed = usb.UsbSpeed;

const reg = @import("registers.zig");
pub const ChannelCharacteristics = reg.ChannelCharacteristics;
pub const ChannelSplitControl = reg.ChannelSplitControl;
pub const ChannelInterrupt = reg.ChannelInterrupt;
pub const DwcTransferSizePid = reg.DwcTransferSizePid;
pub const TransferSize = reg.TransferSize;
pub const ChannelRegisters = reg.ChannelRegisters;

pub const ChannelId = u5;

const Self = @This();

pub const Transfer = struct {
    buffer: []u8 = undefined,
    initial_transfer_size: reg.TransferSize = undefined,
    bytes_remaining: u19 = 0,
    packets_remaining: u10 = 0,

    pub fn prepare(self: *Transfer, buffer: []u8, max_packet_size: PacketSize) void {
        const bytes_remaining: u19 = @truncate(buffer.len);
        const packets_remaining: u10 = @truncate((bytes_remaining + max_packet_size - 1) / max_packet_size);

        self.buffer = buffer;
        self.bytes_remaining = bytes_remaining;
        self.packets_remaining = packets_remaining;
    }
};

pub const CompletionHandler = struct {
    callback: *const fn (*const CompletionHandler, *Self, data: []u8) void,

    fn invoke(self: *const CompletionHandler, channel: *Self, data: []u8) void {
        self.callback(self, channel, data);
    }
};

id: ChannelId = undefined,
registers: *volatile reg.ChannelRegisters = undefined,
state: ChannelState = undefined,
state_spinlock: Spinlock = Spinlock.init("channel state", false),
completion_handler: ?*CompletionHandler = null,
active_transfer: Transfer = .{},

// State transitions:
// Idle -(claim)-> Claimed
// Idle -(channelInterrupt) -> Idle
// Claimed -(transactionBegin)-> Configuring
// Claimed -(channelInterrupt) -> Claimed
// Configuring -(automatic)-> Active
// Active -(channelInterrupt)-> Finalizing
// Active -(timeout)-> Terminating
// Terminating -(channelInterrupt:disabled)-> Finalizing
// Finalizing -(automatic)-> Idle

const ChannelState = enum {
    /// the channel is available and not enabled
    Idle,

    /// the channel has been allocated to a sender
    Claimed,

    /// we are setting up registers for a transaction
    Configuring,

    /// channel is actively sending or receiving data
    Active,

    /// channel is sending or receiving, but application has requested
    /// to disable
    Terminating,

    /// transaction completed or error raised, this is when the
    /// completion callback is invoked
    Finalizing,
};

pub const Error = error{
    Timeout,
    ChannelBusy,
    UnsupportedInitialPid,
};

pub fn init(self: *Self, id: ChannelId, channel_register_base: u64) void {
    self.* = .{
        .id = id,
        .registers = @ptrFromInt(channel_register_base + (@sizeOf(ChannelRegisters) * @as(usize, id))),
    };
    self.state = .Idle;
    self.state_spinlock.enabled = true;
    self.state_spinlock.target_level = .IRQ;
}

pub fn claim(self: *Self) !void {
    self.state_spinlock.acquire();
    defer self.state_spinlock.release();

    if (self.state != .Idle) {
        return Error.ChannelBusy;
    }

    self.state = .Claimed;
}

fn isEnabled(self: *Self) bool {
    return self.registers.channel_character.enable == 1;
}

fn enable(self: *Self) void {
    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.enable = 1;
    channel_characteristics.disable = 0;
    self.registers.channel_character = channel_characteristics;
}

fn disable(self: *Self) void {
    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.enable = 0;
    channel_characteristics.disable = 1;
    self.registers.channel_character = channel_characteristics;
}

const all_one_bits: ChannelInterrupt = @bitCast(@as(u32, 0xffff_ffff));

fn interruptsClearPending(self: *Self) void {
    self.registers.channel_int = all_one_bits;
}

const all_zero_bits: ChannelInterrupt = @bitCast(@as(u32, 0));

fn interruptDisableAll(self: *Self) void {
    std.log.debug("channel {d} interrupt disable all", .{self.id});
    self.registers.channel_int_mask = all_zero_bits;
}

fn interruptsEnableActiveTransaction(self: *Self) void {
    std.log.debug("channel {d} interrupt enable active transaction", .{self.id});
    self.registers.channel_int_mask = .{
        .transfer_completed = 1,
        .halted = 1,
        .ahb_error = 1,
        .stall_response_received = 1,
        .transaction_error = 1,
        .babble_error = 1,
        .frame_overrun = 1,
        .data_toggle_error = 1,
    };
}

// TODO where do we enforce the alignment on the buffer? It must be
// aligned to the DMA alignment (64 bytes on RPi3)
pub fn transactionBegin(
    self: *Self,
    device: DeviceAddress,
    device_speed: UsbSpeed,
    endpoint_number: EndpointNumber,
    endpoint_type: EndpointType,
    endpoint_direction: EndpointDirection,
    max_packet_size: PacketSize,
    initial_pid: usb.PID2,
    buffer: []u8,
    completion_handler: ?*CompletionHandler,
) !void {
    if (self.isEnabled()) {
        return Error.ChannelBusy;
    }

    self.state_spinlock.acquire();
    defer self.state_spinlock.release();

    self.state = .Configuring;
    self.completion_handler = completion_handler;

    self.interruptsClearPending();

    self.active_transfer.prepare(buffer, max_packet_size);

    const dwc_pid: DwcTransferSizePid = switch (initial_pid) {
        .token_setup => .Setup,
        .data_data0 => .Data0,
        .data_data1 => .Data1,
        .data_data2 => .Data2,
        else => return Error.UnsupportedInitialPid,
    };

    self.registers.channel_transfer_size = .{
        .transfer_size_bytes = self.active_transfer.bytes_remaining,
        .transfer_size_packets = self.active_transfer.packets_remaining,
        .pid = dwc_pid,
        .do_ping = 0,
    };

    self.registers.channel_dma_addr = @truncate(@intFromPtr(buffer.ptr));

    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.max_packet_size = max_packet_size;

    // TODO - Is this really 1?
    channel_characteristics.multi_count = 1;
    channel_characteristics.endpoint_direction = switch (endpoint_direction) {
        .out => .out,
        .in => .in,
    };
    channel_characteristics.low_speed_device = switch (device_speed) {
        .Low => 1,
        else => 0,
    };
    channel_characteristics.device_address = device;
    channel_characteristics.endpoint_type = endpoint_type;
    channel_characteristics.endpoint_number = endpoint_number;

    // TODO This only works for non-periodic and non-split
    // transactions
    channel_characteristics.odd_frame = 0;

    self.interruptsEnableActiveTransaction();

    channel_characteristics.enable = 1;
    channel_characteristics.disable = 0;

    // trigger the transaction
    self.registers.channel_character = channel_characteristics;
    self.state = .Active;
}

pub fn channelInterrupt(self: *Self) void {
    std.log.debug("channel {d} interrupt intr 0x{x:0>8} intmsk 0x{x:0>8}", .{ self.id, @as(u32, @bitCast(self.registers.channel_int)), @as(u32, @bitCast(self.registers.channel_int_mask)) });

    if (self.state != .Active and self.state != .Terminating) {
        std.log.warn("channel {d} spurious interrupt while in state {any}. ignoring.", .{ self.id, self.state });
        return;
    }

    self.state_spinlock.acquire();
    defer self.state_spinlock.release();

    const int_status: ChannelInterrupt = @bitCast(@as(u32, @bitCast(self.registers.channel_int)) &
        @as(u32, @bitCast(self.registers.channel_int_mask)));

    switch (self.state) {
        .Active => {
            // We are sending or receiving data. We are waiting for it
            // to finish. The controller signals this with the
            // transfer_completed interrupt
            if (int_status.transfer_completed == 1) {
                self.state = .Finalizing;
                std.log.debug("channel {d} transfer complete", .{self.id});
                std.log.debug("channel {d} tsize 0x{x:0>8}", .{ self.id, @as(u32, @bitCast(self.registers.channel_transfer_size)) });
                self.disable();
                self.interruptsClearPending();
                self.interruptDisableAll();

                // TODO check if all bytes have been transferred
                // if so, call completion handler.
                // if not, restart the channel with the remaining data

                if (self.completion_handler) |h| {
                    h.invoke(self, self.active_transfer.buffer);
                }

                self.idle();
                return;
            }
            std.log.warn("channel {d} spurious interrupt while in state {any} intr 0x{x:0>8}", .{ self.id, self.state, @as(u32, @bitCast(int_status)) });
        },
        .Terminating => {
            // We are waiting for the controller to confirm the
            // channel is halted. It does this by raising the halted
            // interrupt.
            if (int_status.halted == 1) {
                self.registers.channel_int_mask.halted = 0;
                self.state = .Finalizing;
                std.log.debug("channel {d} abort complete", .{self.id});
                self.idle();
            }
            std.log.warn("channel {d} spurious interrupt while in state {any} intr 0x{x:0>8}", .{ self.id, self.state, @as(u32, @bitCast(int_status)) });
        },
        else => {
            std.log.err("channel {d} erroneous interrupt while in state {any} intr 0x{x:0>8}", .{ self.id, self.state, @as(u32, @bitCast(int_status)) });
        },
    }

    // TODO what should we do with the other possible interrupts?
}

fn idle(self: *Self) void {
    self.state = .Idle;
    self.completion_handler = null;
}

pub fn channelAbort(self: *Self) void {
    if (self.state != .Active) {
        std.log.warn("channel {d} attempt to abort, but channel is not active (state is {any})", .{ self.id, self.state });
        return;
    }

    self.state_spinlock.acquire();
    defer self.state_spinlock.release();

    std.log.debug("channel {d} abort requested", .{self.id});

    // listen for only the halted interrupt that tells us the disable
    // request is completed
    self.interruptDisableAll();
    self.registers.channel_int_mask.halted = 1;
    self.state = .Terminating;
    self.disable();
}

pub fn waitForState(self: *Self, clock: *Clock, desired_state: ChannelState, timeout_millis: u32) !void {
    std.log.debug("channel {d} wait {d} ms for state {any}", .{ self.id, timeout_millis, desired_state });

    const start_ticks = clock.ticks();
    const elapsed_ticks = timeout_millis * 1_000; // clock freq is 1Mhz
    const deadline = start_ticks + elapsed_ticks;
    while (self.state != desired_state and clock.ticks() < deadline) {}
    if (self.state != desired_state) {
        std.log.debug("channel {d} timeout waiting for state {any}", .{ self.id, desired_state });
        return Error.Timeout;
    }
    std.log.debug("channel {d} state {any} observed", .{ self.id, desired_state });
}
