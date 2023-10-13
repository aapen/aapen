pub const DMARequest = struct {
    source: u64 = 0,
    destination: u64 = 0,
    length: usize = 0,
    stride: usize = 0,
};

pub const DMAChannel = struct {
    context: *anyopaque,
};

pub const DMAError = error{
    NoAvailableChannel,
    OutOfMemory,
};

/// VTable for DMA controller
pub const DMAController = struct {
    reserveChannel: *const fn (controller: *DMAController) DMAError!DMAChannel,
    initiate: *const fn (controller: *DMAController, channel: DMAChannel, request: *DMARequest) DMAError!void,
    awaitChannel: *const fn (controller: *DMAController, channel: DMAChannel) bool,
    releaseChannel: *const fn (controller: *DMAController, channel: DMAChannel) void,
};
