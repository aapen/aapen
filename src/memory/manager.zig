const root = @import("root");
const printf = root.printf;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

// ----------------------------------------------------------------------
// Allocate and release
// ----------------------------------------------------------------------
pub const Error = error{
    OutOfMemory,
    BadRequest,
    BadFree,
};

pub fn get(bytes: usize) !u64 {
    if (bytes == 0) {
        return error.BadRequest;
    }

    const alloc_size = roundmb(bytes);

    const im = cpu.disable();
    defer cpu.restore(im);

    freelist_lock.acquire();
    defer freelist_lock.release();

    var prev: *Memblock = &freelist;
    var curr: ?*Memblock = prev.next;

    while (curr != null) {
        const currbl = curr.?;
        // _ = printf("    in loop, prev = 0x%08x, prev.next = 0x%08x, curr = 0x%08x\n", @intFromPtr(prev), @intFromPtr(prev.next), @intFromPtr(curr));

        if (currbl.length == alloc_size) {
            prev.next = currbl.next;
            freelist.length -= alloc_size;

            return @intFromPtr(curr);
        } else if (currbl.length > alloc_size) {
            // split the block
            const leftover: *Memblock = @ptrFromInt(@intFromPtr(currbl) + alloc_size);

            //            _ = printf("carving %d bytes off the front of block at 0x%08x (was %d bytes)\n", alloc_size, @intFromPtr(currbl), currbl.length);

            prev.next = leftover;
            leftover.next = currbl.next;
            leftover.length = currbl.length - alloc_size;

            // _ = printf("freelist thinks we have %d bytes left to allocate\n", freelist.length);

            freelist.length -= alloc_size;
            return @intFromPtr(currbl);
        }
        prev = currbl;
        curr = currbl.next;
    }

    return error.OutOfMemory;
}

pub fn free(memptr: u64, bytes: usize) !void {
    // sanity check
    if (bytes == 0 or
        memptr < heap_start or
        memptr > heap_end)
    {
        return error.BadRequest;
    }

    var block: *Memblock = @ptrFromInt(memptr);
    const free_size = roundmb(bytes);

    const im = cpu.disable();
    defer cpu.restore(im);

    freelist_lock.acquire();
    defer freelist_lock.release();

    var prev = &freelist;
    var next = freelist.next;
    while (next != null and @intFromPtr(next) < @intFromPtr(block)) {
        prev = next.?;
        next = next.?.next;
    }

    var top: usize = 0;
    if (prev == &freelist) {
        // freed block goes right at the front
        top = 0;
    } else {
        top = @intFromPtr(prev) + prev.length;
    }

    if (top > @intFromPtr(block) or (next != null and (memptr + free_size) > @intFromPtr(next.?))) {
        return error.BadFree;
    }

    freelist.length += free_size;

    // Coalesce with previous block, if possible
    if (top == @intFromPtr(block)) {
        prev.length += free_size;
        block = prev;
    } else {
        block.next = next;
        block.length = free_size;
        prev.next = block;
    }

    // Now coalesce with next block, if possible
    if (@intFromPtr(block) + block.length == @intFromPtr(next)) {
        // adjacent blocks, we can coalesce
        block.length += next.?.length;
        block.next = next.?.next;
    }
    return;
}

// ----------------------------------------------------------------------
// Freelist
// ----------------------------------------------------------------------
var heap_start: u64 = undefined;
var heap_end: u64 = undefined;

var freelist: Memblock = .{
    .next = null,
    .length = 0,
};

var freelist_lock: TicketLock = TicketLock.initWithTargetLevel("memory", true, .FIQ);

/// initialize freelist
pub fn init(start_addr: u64, end_addr: u64) void {
    const im = cpu.disable();
    defer cpu.restore(im);

    freelist_lock.acquire();
    defer freelist_lock.release();

    // Align the start to 8 bytes
    const freemem_start = roundmb(start_addr);
    const freemem_end = truncmb(end_addr);

    heap_start = freemem_start;
    heap_end = freemem_end;

    const next: *Memblock = @ptrFromInt(freemem_start);
    const length = freemem_end - freemem_start;

    // one node in the list contains the entire heap
    freelist.next = next;
    freelist.length = (length - start_addr);

    // the next node in the linked list lived at the start of the next
    // free block.
    next.next = null;
    next.length = (length - start_addr);
}

// ----------------------------------------------------------------------
// Memory blocks
// ----------------------------------------------------------------------
const BLOCK_MASK = ~@as(u64, 0x07);

const Memblock = struct {
    next: ?*Memblock,
    length: usize,
};

inline fn roundmb(x: u64) u64 {
    return (x + 7) & BLOCK_MASK;
}

inline fn truncmb(x: u64) u64 {
    return x & BLOCK_MASK;
}

// ----------------------------------------------------------------------
// Test support
// ----------------------------------------------------------------------
pub fn dumpFreelist() void {
    const FreelistSnapshot = struct {
        const Entry = struct { u64, u64 };
        var entries: [16]Entry = undefined;
        var count: usize = 0;
    };

    // Snapshot the freelist before displaying it. (Display can scroll
    // which causes allocation. It's a Heisenberg situation.)
    {
        freelist_lock.acquire();
        defer freelist_lock.release();

        var i: usize = 0;
        var head: ?*Memblock = &freelist;
        while (head != null and i < 16) {
            FreelistSnapshot.entries[i][0] = @intFromPtr(head.?.next);
            FreelistSnapshot.entries[i][1] = head.?.length;
            head = head.?.next;
            i += 1;
        }
        FreelistSnapshot.count = i;
    }

    // Display now that we've unlocked the freelist.
    _ = printf("freelist [\n");
    for (0..FreelistSnapshot.count) |i| {
        _ = printf("    [0x%08x : 0x%08x bytes]\n", FreelistSnapshot.entries[i][0], FreelistSnapshot.entries[i][1]);
    }
    _ = printf("]\n");
}
