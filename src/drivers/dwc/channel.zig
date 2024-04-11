const std = @import("std");

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
const TransferRequest = usb.TransferRequest;
const TransferBytes = usb.TransferBytes;
const TransferType = usb.TransferType;
const UsbSpeed = usb.UsbSpeed;

const reg = @import("registers.zig");
const ChannelCharacteristics = reg.ChannelCharacteristics;
const ChannelSplitControl = reg.ChannelSplitControl;
const ChannelInterrupt = reg.ChannelInterrupt;
const DwcTransferSizePid = reg.DwcTransferSizePid;
const TransferSize = reg.Transfer;
const ChannelRegisters = reg.ChannelRegisters;

pub const ChannelId = u5;

const Self = @This();

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

host: *Host = undefined,
id: ChannelId = undefined,
registers: *volatile reg.ChannelRegisters = undefined,
completion_handler: ?*CompletionHandler = null,
active_transfer: ?*TransferRequest = null,
aligned_buffer: []u8 = undefined,

pub const Error = error{
    Timeout,
    ChannelBusy,
    UnsupportedInitialPid,
};

pub fn init(self: *Self, host: *Host, id: ChannelId, registers: *volatile ChannelRegisters, aligned_buffer: []u8) void {
    self.* = .{
        .host = host,
        .id = id,
        .registers = registers,
        .aligned_buffer = aligned_buffer,
        .completion_handler = null,
        .active_transfer = null,
    };
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
    // Host.log.debug(@src(),"channel {d} interrupt disable all", .{self.id});
    self.registers.channel_int_mask = all_zero_bits;
}

pub fn interruptsEnableActiveTransaction(self: *Self) void {
    // Host.log.debug(@src(),"channel {d} interrupt enable active transaction", .{self.id});
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

const InterruptReason = enum {
    transfer_failed,
    transfer_needs_restart,
    transaction_needs_restart,
    transfer_needs_defer,
    transfer_completed,
};

pub fn channelInterrupt2(self: *Self, host: *Host) void {
    if (self.active_transfer == null) {
        Host.log.debug(@src(), "channel {d} received a spurious interrupt.", .{self.id});
        return;
    }

    const req: *TransferRequest = self.active_transfer.?;
    const int_status: ChannelInterrupt = self.registers.channel_int;
    var interrupt_reason: InterruptReason = undefined;

    var buf = std.mem.zeroes([128]u8);
    const l = int_status.debugDecode(&buf);
    Host.log.debug(@src(), "channel {d} interrupt{s}, characteristics 0x{x:0>8}, transfer 0x{x:0>8}", .{
        self.id,
        buf[0..l],
        @as(u32, @bitCast(self.registers.channel_character)),
        @as(u32, @bitCast(self.registers.transfer)),
    });

    if (int_status.stall == 1 or int_status.ahb_error == 1 or int_status.transaction_error == 1 or
        int_status.babble_error == 1 or int_status.excessive_transmission == 1 or
        int_status.frame_list_rollover == 1 or
        (int_status.nyet == 1 and !req.complete_split) or
        (int_status.data_toggle_error == 1 and self.registers.channel_character.endpoint_direction == EndpointDirection.out))
    {
        Host.log.err(@src(), "channel {d} transfer error (interrupts = 0x{x:0>8},  packet count = {d})", .{ self.id, @as(u32, @bitCast(int_status)), self.registers.transfer.packet_count });

        self.host.dumpStatus();
        self.channelStatus();

        interrupt_reason = .transfer_failed;
    } else if (int_status.frame_overrun == 1) {
        // Host.log.debug(@src(),"channel {d} frame overrun. restarting transaction", .{self.id});
        interrupt_reason = .transaction_needs_restart;
    } else if (int_status.nyet == 1) {
        // Host.log.debug(@src(),"channel {d} received nyet from device; split retry needed", .{self.id});
        req.csplit_retries += 1;
        if (req.csplit_retries > 10) {
            // Host.log.debug(@src(),"channel {d} restarting split transaction (CSPLIT tried {d} times)", .{ self.id, req.csplit_retries });
            req.complete_split = false;
        }
        interrupt_reason = .transaction_needs_restart;
    } else if (int_status.nak == 1) {
        // Host.log.debug(@src(),"channel {d} received nak from
        // device; deferring transfer", .{self.id});
        req.nak_count += 1;

        if (req.nak_count > 5) {
            // temporary while testing
            interrupt_reason = .transfer_failed;
        } else {
            interrupt_reason = .transfer_needs_defer;
            req.complete_split = false;
        }
    } else {
        interrupt_reason = self.channelHaltedNormal(req, int_status);
    }

    Host.log.debug(@src(), "channel {d} interrupt_reason {s}", .{ self.id, @tagName(interrupt_reason) });

    var completion: TransferRequest.CompletionStatus = undefined;

    switch (interrupt_reason) {
        .transfer_completed => completion = .ok,
        .transfer_failed => completion = .failed,
        .transfer_needs_defer => {},
        .transfer_needs_restart => {
            host.channelStartTransfer(self, req);
            return;
        },
        .transaction_needs_restart => {
            host.channelStartTransaction(self, req);
            return;
        },
    }

    // transfer either finished, encountered an error, or needs to be
    // retried later.

    // This is some odd cleanup... we're telling the host to
    // deallocate this channel. (We don't want to keep the channel reserved
    // while deferring a retry. Some other transfer might need the channel.)
    req.next_data_pid = self.registers.transfer.packet_id;
    self.interruptDisableAll();
    self.interruptsClearPending();

    self.active_transfer = null;
    host.channelFree(self);

    if (!req.isControlRequest() or req.control_phase == TransferRequest.control_data_phase) {
        req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
    }

    if (interrupt_reason == .transfer_needs_defer) {
        if (host.deferTransfer(req)) {
            return;
        } else |_| {
            completion = .failed;
        }
    }

    req.complete(completion);
}

fn channelHaltedNormal(self: *Self, req: *TransferRequest, ints: ChannelInterrupt) InterruptReason {
    const packets_remaining = self.registers.transfer.packet_count;
    const packets_transferred = req.attempted_packets_remaining - packets_remaining;
    const bytes_remaining = self.registers.transfer.size;
    _ = bytes_remaining;

    // Host.log.debug(@src(),"channel {d} reports packets_remaining {d}", .{ self.id, packets_remaining });
    // Host.log.debug(@src(),"channel {d} packets remaining {d} of {d}, so packets transferred {d}", .{ self.id, packets_remaining, req.attempted_packets_remaining, packets_transferred });

    if (packets_transferred != 0) {
        var bytes_transferred: TransferBytes = 0;
        const char = self.registers.channel_character;
        const max_packet_size = char.max_packet_size;
        const dir = char.endpoint_direction;
        const ty = char.endpoint_type;

        if (dir == EndpointDirection.in) {
            bytes_transferred = req.attempted_bytes_remaining - self.registers.transfer.size;

            if (!Host.isAligned(req.cur_data_ptr.?)) {
                // we're reading into a different buffer than the
                // original caller provided. copy the results from our
                // DMA aligned buffer to the one the caller can see
                const start_pos = req.attempted_size - req.attempted_bytes_remaining;
                @memcpy(req.cur_data_ptr.?, self.aligned_buffer[start_pos .. start_pos + bytes_transferred]);
            }
        } else {
            // hardware doesn't properly update transfer registers'
            // size field for OUT transfers
            if (packets_transferred > 1) {
                bytes_transferred += max_packet_size * (packets_transferred - 1);
            }

            if (packets_remaining == 0 and
                (req.attempted_size % max_packet_size != 0 or req.attempted_size == 0))
            {
                bytes_transferred += req.attempted_size % max_packet_size;
            } else {
                bytes_transferred += max_packet_size;
            }
        }

        // Host.log.debug(@src(),"channel {d} calculated {d} bytes transferred", .{ self.id, bytes_transferred });

        req.attempted_packets_remaining -= packets_transferred;
        req.attempted_bytes_remaining -= bytes_transferred;
        req.cur_data_ptr.? += bytes_transferred;

        //        Host.log.debug(@src(),"channel {d} packets remaining {d}, bytes remaining {d}", .{ self.id, req.attempted_packets_remaining, req.attempted_bytes_remaining });

        // is the transfer completed?
        if (req.attempted_packets_remaining == 0 or
            (dir == EndpointDirection.in and
            bytes_transferred < packets_transferred * max_packet_size))
        {
            if (ints.transfer_complete == 0) {
                Host.log.err(@src(), "channel {d} expected transfer_completed flag but was not observed.", .{self.id});
                return .transfer_failed;
            }

            if (req.short_attempt and
                req.attempted_bytes_remaining == 0 and
                ty != TransferType.interrupt)
            {
                Host.log.debug(@src(), "channel {d} starting next part of {d} byte transfer, after short attempt of {d} bytes", .{ self.id, req.size, req.attempted_size });
                req.complete_split = false;
                req.next_data_pid = self.registers.transfer.packet_id;
                if (!req.isControlRequest() or
                    req.control_phase == TransferRequest.control_data_phase)
                {
                    req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
                }
                return .transfer_needs_restart;
            }

            if (req.isControlRequest() and req.control_phase < 2) {
                req.complete_split = false;
                if (req.control_phase == TransferRequest.control_data_phase) {
                    req.actual_size = @truncate(@intFromPtr(req.cur_data_ptr.?) - @intFromPtr(req.data));
                }

                req.control_phase += 1;

                if (req.control_phase == TransferRequest.control_data_phase and req.size == 0) {
                    req.control_phase += 1;
                }
                return .transfer_needs_restart;
            }

            Host.log.debug(@src(), "channel {d} transfer completed", .{self.id});
            return .transfer_completed;
        } else {
            // transfer not complete, start the next transaction
            if (self.registers.split_control.split_enable == 1) {
                req.complete_split = !req.complete_split;
            }

            Host.log.debug(@src(), "channel {d} will continue transfer", .{self.id});
            return .transaction_needs_restart;
        }
    } else {
        // no packets transferred. also no error. it's a split thing.
        if (ints.ack == 1 and
            self.registers.split_control.split_enable == 1 and
            !req.complete_split)
        {
            // Start CSPLIT
            req.complete_split = true;
            Host.log.debug(@src(), "channel {d} must continue transfer (complete_split = {})", .{ self.id, req.complete_split });
            return .transaction_needs_restart;
        } else if (req.isControlRequest() and req.control_phase == TransferRequest.control_status_phase) {
            Host.log.debug(@src(), "channel {d} status phase completed", .{self.id});
            return .transfer_completed;
        } else {
            Host.log.err(@src(), "channel {d} no packets transferred", .{self.id});
            return .transfer_failed;
        }
    }
}

pub fn channelAbort(self: *Self) void {
    if (self.state != .Active) {
        Host.log.warn(@src(), "channel {d} attempt to abort, but channel is not active (state is {any})", .{ self.id, self.state });
        return;
    }

    const im = cpu.disable();
    defer cpu.restore(im);

    Host.log.debug(@src(), "channel {d} abort requested", .{self.id});

    // listen for only the halted interrupt that tells us the disable
    // request is completed
    self.interruptDisableAll();
    self.registers.channel_int_mask.halt = 1;
    self.state = .Terminating;
    self.disable();
}

pub fn channelStatus(self: *Self) void {
    Host.log.info(@src(), "{s: >28}", .{"Channel registers"});
    dumpRegisterPair("characteristics", @bitCast(self.registers.channel_character), "split_control", @bitCast(self.registers.split_control));
    dumpRegisterPair("interrupt", @bitCast(self.registers.channel_int), "int. mask", @bitCast(self.registers.channel_int_mask));
    dumpRegisterPair("transfer", @bitCast(self.registers.transfer), "dma addr", @bitCast(self.registers.channel_dma_addr));
}

pub fn dumpRegisterPair(f1: []const u8, v1: u32, f2: []const u8, v2: u32) void {
    Host.log.info(@src(), "{s: >28}: {x:0>8}\t{s: >28}: {x:0>8}", .{ f1, v1, f2, v2 });
}
