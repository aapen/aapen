const std = @import("std");

pub const OneShot = @import("synchronize/oneshot.zig");
pub const TicketLock = @import("synchronize/ticketlock.zig");

// ----------------------------------------------------------------------
// Architecture-specific constants
// ----------------------------------------------------------------------
const root = @import("root");
const data_cache_line_length = root.HAL.data_cache_line_length;

// ----------------------------------------------------------------------
// Cache coherence and maintenance
// ----------------------------------------------------------------------
pub fn dataCacheSliceClean(buf: []u8) void {
    dataCacheRangeClean(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeClean(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc cvac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}

pub fn dataCacheSliceInvalidate(buf: []u8) void {
    dataCacheRangeInvalidate(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeInvalidate(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc ivac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}

pub fn dataCacheSliceCleanAndInvalidate(buf: []u8) void {
    dataCacheRangeCleanAndInvalidate(@intFromPtr(buf.ptr), buf.len);
}

pub fn dataCacheRangeCleanAndInvalidate(address: u64, length: u64) void {
    var next_location = address;
    var remaining_length = length + data_cache_line_length;

    while (true) {
        asm volatile (
            \\ dc civac, %[addr]
            :
            : [addr] "r" (next_location),
        );

        if (remaining_length < data_cache_line_length) {
            break;
        }

        next_location += data_cache_line_length;
        remaining_length -= data_cache_line_length;
    }
}
