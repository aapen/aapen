const frame_buffer = @import("../../frame_buffer.zig");
const FrameBuffer = frame_buffer.FrameBuffer;

pub const VideoController = struct {
    allocFrameBuffer: *const fn (video_controller: *VideoController, fb: *FrameBuffer, xres: u32, yres: u32, depth: u32, palette: []const u32) void,
};
