const board_info = @import("interfaces/board_info.zig");
pub const BoardInfo = board_info.BoardInfo;
pub const BoardInfoController = board_info.BoardInfoController;

const clock = @import("interfaces/clock.zig");
pub const Clock = clock.Clock;
pub const Timer = clock.Timer;
pub const TimerCallbackFn = clock.TimerCallbackFn;

const dma = @import("interfaces/dma.zig");
pub const DMARequest = dma.DMARequest;
pub const DMAChannel = dma.DMAChannel;
pub const DMAError = dma.DMAError;
pub const DMAController = dma.DMAController;

const serial = @import("interfaces/serial.zig");
pub const Serial = serial.Serial;

const video_controller = @import("interfaces/video_controller.zig");
pub const VideoController = video_controller.VideoController;
