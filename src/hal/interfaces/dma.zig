pub const DMARequest = struct {
    source: u32 = 0,
    source_increment: bool = true,
    destination: u32 = 0,
    destination_increment: bool = true,
    length: usize = 0,
    stride: usize = 0,
};

pub const DMAChannel = struct {
    owner: *DMAController,
    context: *anyopaque,
};

pub const DMAError = error{
    NoAvailableChannel,
    OutOfMemory,
};

/// VTable for DMA controller
pub const DMAController = struct {
    reserveChannel: *const fn (controller: *DMAController) DMAError!DMAChannel,
    createRequest: *const fn (controller: *DMAController) DMAError!*DMARequest,
    destroyRequest: *const fn (controller: *DMAController, request: *DMARequest) void,
    initiate: *const fn (controller: *DMAController, channel: DMAChannel, request: *DMARequest) DMAError!void,
    awaitChannel: *const fn (controller: *DMAController, channel: DMAChannel) bool,
    releaseChannel: *const fn (controller: *DMAController, channel: DMAChannel) void,
};
