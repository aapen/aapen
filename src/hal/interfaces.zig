const serial = @import("interfaces/serial.zig");
pub const Serial = serial.Serial;

const clock = @import("interfaces/clock.zig");
pub const Clock = clock.Clock;
pub const Timer = clock.Timer;
pub const TimerCallbackFn = clock.TimerCallbackFn;

const dma = @import("interfaces/dma.zig");
pub const DMARequest = dma.DMARequest;
pub const DMAChannel = dma.DMAChannel;
pub const DMAError = dma.DMAError;
pub const DMAController = dma.DMAController;
