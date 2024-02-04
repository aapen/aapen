const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const root = @import("root");
const printf = root.printf;

const heap = @import("../heap.zig");
const memory = @import("../memory.zig");

pub fn testBody() !void {
    reportHeapBounds();
    try freelistInit();
    try memgetSingle();
    try memgetRepeatSmallBlocks();
    try getAndFree();
    try getAndFreeOutOfOrder();
}

fn initializeMemory() void {
    // reset before each test
    memory.init(@intFromPtr(root.HAL.heap_start), root.HAL.heap_end);
}

fn reportHeapBounds() void {
    initializeMemory();
    // _ = printf("start = 0x%08x\nend = 0x%08x\n", @intFromPtr(root.HAL.heap_start), root.HAL.heap_end);
}

fn freelistInit() !void {
    initializeMemory();
    memory.dumpFreelist();
}

fn memgetSingle() !void {
    initializeMemory();

    const size: usize = 128;

    const block: u64 = try memory.get(size);
    expect(block > 0);
    // _ = printf("requested %d:  received it at 0x%08x\n", size, block);
    // memory.dumpFreelist();
}

fn memgetRepeatSmallBlocks() !void {
    initializeMemory();

    const size: usize = 1024;

    for (0..40) |i| {
        _ = i;
        // _ = printf("... %d ", i);
        const block: u64 = try memory.get(size);
        expect(block > 0);
        // _ = printf("requested %d:  received it at 0x%08x\n", size, block);
        // memory.dumpFreelist();
    }
}

fn getAndFree() !void {
    initializeMemory();

    const size: usize = 2048;

    _ = printf("allocate 3 blocks of size %d\n", size);

    const r1 = try memory.get(size);
    const r2 = try memory.get(size);
    const r3 = try memory.get(size);

    memory.dumpFreelist();

    _ = printf("free them in reverse order\n");
    try memory.free(r3, size);
    try memory.free(r2, size);
    try memory.free(r1, size);

    memory.dumpFreelist();
}

fn getAndFreeOutOfOrder() !void {
    initializeMemory();

    const size: usize = 4096;

    _ = printf("allocate 10 blocks of size %d\n", size);

    const r1 = try memory.get(size);
    const r2 = try memory.get(size);
    const r3 = try memory.get(size);
    const r4 = try memory.get(size);
    const r5 = try memory.get(size);
    const r6 = try memory.get(size);
    const r7 = try memory.get(size);
    const r8 = try memory.get(size);
    const r9 = try memory.get(size);
    const r10 = try memory.get(size);

    memory.dumpFreelist();

    _ = printf("free them in a scattered order\n");
    try memory.free(r3, size);
    try memory.free(r2, size);
    try memory.free(r1, size);
    try memory.free(r9, size);
    try memory.free(r7, size);
    try memory.free(r6, size);
    try memory.free(r8, size);
    try memory.free(r4, size);
    try memory.free(r5, size);
    try memory.free(r10, size);

    memory.dumpFreelist();
}
