const std = @import("std");
const log = std.log.scoped(.dwc_otg_usb_channel);

const root = @import("root");

const arch = @import("../../architecture.zig");
const cpu = arch.cpu;

const Host = @import("../dwc_otg_usb.zig");

const synchronize = @import("../../synchronize.zig");
const time = @import("../../time.zig");

const usb = @import("../../usb.zig");
const DeviceAddress = usb.DeviceAddress;
const EndpointDirection = usb.EndpointDirection;
const EndpointNumber = usb.EndpointNumber;
const PacketSize = usb.PacketSize;
const PID = usb.PID2;
const Transfer = usb.Transfer;
const TransferBytes = usb.TransferBytes;
const TransferType = usb.TransferType;
const UsbSpeed = usb.UsbSpeed;

const reg = @import("registers.zig");
const ChannelCharacteristics = reg.ChannelCharacteristics;
const ChannelSplitControl = reg.ChannelSplitControl;
const ChannelInterrupt = reg.ChannelInterrupt;
const DwcTransferSizePid = reg.DwcTransferSizePid;
const TransferSize = reg.TransferSize;
const ChannelRegisters = reg.ChannelRegisters;

pub const ChannelId = u5;

const Self = @This();

// pub const Transfer = struct {
//     buffer: []u8 = undefined,
//     initial_transfer_size: reg.TransferSize = undefined,
//     bytes_remaining: u19 = 0,
//     packets_remaining: u10 = 0,

//     pub fn prepare(self: *Transfer, buffer: []u8, max_packet_size: PacketSize) void {
//         const bytes_remaining: u19 = @truncate(buffer.len);
//         const packets_remaining: u10 = @truncate((bytes_remaining + max_packet_size - 1) / max_packet_size);

//         self.buffer = buffer;
//         self.bytes_remaining = bytes_remaining;
//         self.packets_remaining = packets_remaining;
//     }
// };

pub const CompletionHandler = struct {
    callbackCompleted: *const fn (*const CompletionHandler, *Self, data: []u8) void,
    callbackHalted: *const fn (*const CompletionHandler, *Self) void,

    fn completed(self: *const CompletionHandler, channel: *Self, data: []u8) void {
        self.callbackCompleted(self, channel, data);
    }

    fn halted(self: *const CompletionHandler, channel: *Self) void {
        self.callbackHalted(self, channel);
    }
};

id: ChannelId = undefined,
registers: *volatile reg.ChannelRegisters = undefined,
state: ChannelState = undefined,
completion_handler: ?*CompletionHandler = null,
active_transfer: ?*Transfer = null,

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

pub fn init(self: *Self, id: ChannelId, registers: *volatile ChannelRegisters) void {
    self.* = .{
        .id = id,
        .registers = registers,
    };
    self.state = .Idle;
}

pub fn claim(self: *Self) !void {
    const im = cpu.disable();
    defer cpu.restore(im);

    if (self.state != .Idle) {
        return Error.ChannelBusy;
    }

    self.state = .Claimed;
}

fn isEnabled(self: *Self) bool {
    return self.registers.channel_character.enable == 1;
}

pub fn enable(self: *Self) void {
    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.enable = 1;
    channel_characteristics.disable = 0;
    self.registers.channel_character = channel_characteristics;
}

pub fn disable(self: *Self) void {
    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.enable = 0;
    channel_characteristics.disable = 1;
    self.registers.channel_character = channel_characteristics;
}

const all_one_bits: ChannelInterrupt = @bitCast(@as(u32, 0xffff_ffff));

pub fn interruptsClearPending(self: *Self) void {
    self.registers.channel_int = all_one_bits;
}

const all_zero_bits: ChannelInterrupt = @bitCast(@as(u32, 0));

pub fn interruptDisableAll(self: *Self) void {
    log.debug("channel {d} interrupt disable all", .{self.id});
    self.registers.channel_int_mask = all_zero_bits;
}

pub fn interruptsEnableActiveTransaction(self: *Self) void {
    log.debug("channel {d} interrupt enable active transaction", .{self.id});
    self.registers.channel_int_mask = .{
        .transfer_complete = 1,
        .halt = 1,
        .ahb_error = 1,
        .stall = 1,
        .nak = 1,
        .ack = 1,
        .nyet = 1,
        .transaction_error = 1,
        .babble_error = 1,
        .frame_overrun = 1,
        .data_toggle_error = 1,
        .buffer_not_available = 1,
        .excessive_transmission = 1,
        .frame_list_rollover = 1,
    };
}

// TODO where do we enforce the alignment on the buffer? It must be
// aligned to the DMA alignment (64 bytes on RPi3)
pub fn transactionBegin(
    self: *Self,
    device: DeviceAddress,
    device_speed: UsbSpeed,
    endpoint_number: EndpointNumber,
    endpoint_type: u2,
    endpoint_direction: u1,
    max_packet_size: PacketSize,
    initial_pid: u4,
    buffer: []u8,
    completion_handler: ?*CompletionHandler,
) !void {
    if (self.isEnabled()) {
        return Error.ChannelBusy;
    }

    if (endpoint_direction == EndpointDirection.out) {
        log.debug("channel {d} request type {d} device {d} sending {d} bytes starting at 0x{x:0>8}", .{ self.id, endpoint_type, device, buffer.len, @intFromPtr(buffer.ptr) });
        root.debug.sliceDump(buffer);
    } else {
        log.debug("channel {d} request type {d} device {d} receiving {d} bytes into 0x{x:0>8}", .{ self.id, endpoint_type, device, buffer.len, @intFromPtr(buffer.ptr) });
    }

    // Don't allow IRQs while we're configuring the channel
    const im = cpu.disable();
    defer cpu.restore(im);

    self.state = .Configuring;

    self.completion_handler = completion_handler;

    self.interruptsClearPending();

    self.active_transfer.?.prepare(buffer, max_packet_size);

    const dwc_pid: DwcTransferSizePid = switch (initial_pid) {
        PID.token_setup => .Setup,
        PID.data_data0 => .Data0,
        PID.data_data1 => .Data1,
        PID.data_data2 => .Data2,
        else => .Data0, // TODO what should we really put here?
    };

    // We build the struct in a stack variable first, then assign it
    // atomically to the chip's register. Otherwise we get 4 separate
    // read-modify-write operations.
    const tsize: TransferSize = .{
        .transfer_size_bytes = self.active_transfer.?.bytes_remaining,
        .transfer_size_packets = self.active_transfer.?.packets_remaining,
        .pid = dwc_pid,
        .do_ping = 0,
    };

    self.registers.channel_transfer_size = tsize;

    // Make sure the HCD can see pending changes
    synchronize.dataCacheSliceCleanAndInvalidate(buffer);

    const bus_address: u32 = @truncate(@intFromPtr(buffer.ptr));
    self.registers.channel_dma_addr = bus_address;

    var channel_characteristics = self.registers.channel_character;
    channel_characteristics.max_packet_size = max_packet_size;

    // TODO - Is this really 1?
    channel_characteristics.packets_per_frame = 1;
    channel_characteristics.endpoint_direction = endpoint_direction;
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

const InterruptReason = enum {
    transfer_failed,
    transfer_needs_restart,
    transaction_needs_restart,
    transfer_needs_defer,
    transfer_completed,
};

pub fn channelInterrupt2(self: *Self, host: *Host) void {
    if (self.active_transfer == null) {
        log.debug("channel {d} received a spurious interrupt.", .{self.id});
        return;
    }

    const xfer: *Transfer = self.active_transfer.?;
    const int_status: ChannelInterrupt = self.registers.channel_int;
    const int_mask: ChannelInterrupt = self.registers.channel_int_mask;
    var interrupt_reason: InterruptReason = undefined;

    log.debug("channel {d} state {s} intsts 0x{x:0>8} intmsk 0x{x:0>8}", .{ self.id, @tagName(self.state), @as(u32, @bitCast(int_status)), @as(u32, @bitCast(int_mask)) });
    int_status.debugDecode();

    // if (int_status.isStatusError() or (int_status.data_toggle_error == 1 and self.registers.channel_character.endpoint_direction == EndpointDirection.out)) {
    //     log.err("channel {d} transfer error (packet count {d})", .{
    //         self.id,
    //         self.registers.channel_transfer_size.transfer_size_packets,
    //     });
    //     interrupt_reason = .transfer_failed;
    // } else

    if (int_status.frame_overrun == 1) {
        log.debug("channel {d} frame overrun. restarting transaction", .{self.id});
        interrupt_reason = .transfer_needs_restart;
    } else if (int_status.nyet == 1) {
        log.debug("channel {d} received nyet from device; split retry needed", .{self.id});
        log.debug("TODO -- handle splits", .{});
    } else if (int_status.nak == 1) {
        log.debug("channel {d} received nak from device; deferring transfer", .{self.id});
        interrupt_reason = .transfer_needs_defer;
    } else {
        interrupt_reason = self.channelHaltedNormal(xfer, int_status);
    }

    var completion: Transfer.CompletionStatus = undefined;

    switch (interrupt_reason) {
        .transfer_completed => completion = .ok,
        .transfer_failed => completion = .hardware_error,
        .transfer_needs_defer => {},
        .transfer_needs_restart => {
            host.channelStartTransfer(self, xfer);
            return;
        },
        .transaction_needs_restart => {
            host.channelStartTransaction(self, xfer);
            return;
        },
    }

    // transfer either finished, encountered an error, or needs to be
    // retried later.

    // This is some odd cleanup... we're telling the host to
    // deallocate this channel. (We don't want to keep the channel reserved
    // while deferring a retry. Some other transfer might need the channel.)
    xfer.next_data_pid = self.registers.channel_transfer_size.pid;
    self.interruptDisableAll();
    self.interruptsClearPending();

    self.active_transfer = null;
    host.channelFree(self);

    if (xfer.endpoint_type != TransferType.control or xfer.control_phase != Transfer.ControlPhase.data) {
        xfer.actual_size = xfer.bytes_transferred;
    }

    if (interrupt_reason == .transfer_needs_defer) {
        if (host.deferTransfer(xfer)) {
            return;
        } else |_| {
            completion = .hardware_error;
        }
    }

    xfer.complete(completion);
}

fn channelHaltedNormal(self: *Self, xfer: *Transfer, ints: ChannelInterrupt) InterruptReason {
    const packets_remaining = self.registers.channel_transfer_size.transfer_size_packets;
    const packets_transferred = xfer.attempted_packets_remaining - packets_remaining;
    const bytes_remaining = self.registers.channel_transfer_size.transfer_size_bytes;
    _ = bytes_remaining;

    log.debug("channel {d} reports packets_remaining {d}", .{ self.id, packets_remaining });
    log.debug("channel {d} calculated {d} packets transferred", .{ self.id, packets_transferred });

    if (packets_transferred != 0) {
        var bytes_transferred: TransferBytes = 0;
        const char = self.registers.channel_character;
        const max_packet_size = char.max_packet_size;
        const dir = char.endpoint_direction;
        const ty = char.endpoint_type;

        if (dir == EndpointDirection.in) {
            bytes_transferred = xfer.attempted_bytes_remaining - self.registers.channel_transfer_size.transfer_size_bytes;
        } else {
            // hardware doesn't properly update transfer registers'
            // size field.
            if (packets_transferred > 1) {
                bytes_transferred += max_packet_size * (packets_transferred - 1);
            }

            if (packets_remaining == 0 and
                (xfer.attempted_size % max_packet_size != 0 or xfer.attempted_size == 0))
            {
                bytes_transferred += xfer.attempted_size % max_packet_size;
            } else {
                bytes_transferred += max_packet_size;
            }
        }

        log.debug("channel {d} calculated {d} bytes transferred", .{ self.id, bytes_transferred });

        xfer.attempted_packets_remaining -= packets_transferred;
        xfer.attempted_bytes_remaining -= bytes_transferred;
        xfer.bytes_transferred += bytes_transferred;

        // is the transfer completed?
        if (xfer.attempted_packets_remaining == 0 or
            (dir == EndpointDirection.in and
            bytes_transferred < packets_transferred * max_packet_size))
        {
            if (ints.transfer_complete == 0) {
                log.err("channel {d} expected transfer_completed flag but was not observed.", .{self.id});
                return .transfer_failed;
            }

            if (xfer.short_attempt and xfer.attempted_bytes_remaining == 0 and ty != TransferType.interrupt) {
                log.debug("channel {d} starting next part of {d} byte transfer, after short attempt of {d} bytes", .{ self.id, xfer.data_buffer.len, xfer.attempted_size });
                // xfer.complete_split = 0;
                xfer.next_data_pid = self.registers.channel_transfer_size.pid;
                if (xfer.endpoint_type != TransferType.control or xfer.control_phase != Transfer.ControlPhase.data) {
                    xfer.actual_size = xfer.bytes_transferred;
                }
                return .transfer_needs_restart;
            }

            if (xfer.endpoint_type == TransferType.control and xfer.control_phase < 2) {
                // xfer.complete_split = 0;
                if (xfer.control_phase == 1) {
                    xfer.actual_size = xfer.bytes_transferred;
                }
                xfer.control_phase += 1;

                if (xfer.control_phase == Transfer.ControlPhase.data and xfer.data_buffer.len == 0) {
                    xfer.control_phase += 1;
                }
                return .transfer_needs_restart;
            }

            log.debug("channel {d} transfer completed", .{self.id});
            return .transfer_completed;
        } else {
            // transfer not complete, start the next transaction
            log.debug("channel {d} will continue transfer", .{self.id});
            return .transaction_needs_restart;
        }
    } else {
        // no packets transferred. also no error. it's a split thing.
        log.err("channel {d} no packets transferred", .{self.id});
        return .transfer_failed;
    }
}

pub fn channelInterrupt(self: *Self) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    const int_status: ChannelInterrupt = self.registers.channel_int;
    const int_mask: ChannelInterrupt = self.registers.channel_int_mask;

    log.debug("channel {d} state {s} intsts 0x{x:0>8} intmsk 0x{x:0>8}", .{ self.id, @tagName(self.state), @as(u32, @bitCast(int_status)), @as(u32, @bitCast(int_mask)) });
    int_status.debugDecode();

    switch (self.state) {
        .Active => {
            // We are sending or receiving data. We are waiting for it
            // to finish. The controller signals this with the
            // transfer_completed interrupt
            if (int_status.transfer_complete == 1) {
                self.state = .Finalizing;

                // interrupt bit is W1C (write 1 to clear)
                self.registers.channel_int.transfer_complete = 1;

                log.debug("channel {d} transfer complete", .{self.id});

                self.disable();
                self.interruptsClearPending();
                self.interruptDisableAll();

                // Make sure the CPU can see updated data
                synchronize.dataCacheSliceInvalidate(self.active_transfer.buffer);

                // TODO check if all bytes have been transferred
                // if so, call completion handler.
                // if not, restart the channel with the remaining data

                if (self.completion_handler) |h| {
                    h.completed(self, self.active_transfer.buffer);
                }

                self.idle();
                return;
            }
            if (int_status.halt == 1) {
                log.debug("channel {d} halted, chintsts 0x{x:0>8}, xfersize 0x{x:0>8}", .{ self.id, @as(u32, @bitCast(self.registers.channel_int)), @as(u32, @bitCast(self.registers.channel_transfer_size)) });

                // TODO what should we do here? restart? call the
                // completion handler with a failed status?

                // interrupt bit is W1C
                self.registers.channel_int.halt = 1;

                if (self.completion_handler) |h| {
                    h.halted(self);
                }

                self.disable();
                self.interruptsClearPending();
                self.interruptDisableAll();
                self.idle();

                return;
            }
        },
        .Terminating => {
            // We are waiting for the controller to confirm the
            // channel is halted. It does this by raising the halted
            // interrupt.
            if (int_status.halt == 1) {
                // interrupt bit is W1C
                self.registers.channel_int.halt = 1;
                self.registers.channel_int_mask.halt = 0;
                self.state = .Finalizing;
                log.debug("channel {d} abort complete", .{self.id});
                self.idle();
                return;
            }
        },
        else => {},
    }

    // TODO what should we do with the other possible interrupts?

    log.warn("channel {d} spurious interrupt while in state {any} intr 0x{x:0>8}", .{ self.id, self.state, @as(u32, @bitCast(int_status)) });
}

fn idle(self: *Self) void {
    self.state = .Idle;
    self.completion_handler = null;
}

pub fn channelAbort(self: *Self) void {
    if (self.state != .Active) {
        log.warn("channel {d} attempt to abort, but channel is not active (state is {any})", .{ self.id, self.state });
        return;
    }

    const im = cpu.disable();
    defer cpu.restore(im);

    log.debug("channel {d} abort requested", .{self.id});

    // listen for only the halted interrupt that tells us the disable
    // request is completed
    self.interruptDisableAll();
    self.registers.channel_int_mask.halt = 1;
    self.state = .Terminating;
    self.disable();
}

pub fn waitForState(self: *Self, desired_state: ChannelState, timeout_millis: u32) !void {
    log.debug("channel {d} wait {d} ms for state {any}", .{ self.id, timeout_millis, desired_state });

    // TODO should probably use a critical section here.
    const deadline = time.deadlineMillis(timeout_millis);
    while (self.state != desired_state and time.ticks() < deadline) {}
    if (self.state != desired_state) {
        log.debug("channel {d} timeout waiting for state {any}", .{ self.id, desired_state });
        return Error.Timeout;
    }
    log.debug("channel {d} state {any} observed", .{ self.id, desired_state });
}
