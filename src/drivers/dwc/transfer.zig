const usb = @import("../usb.zig");
const Device = usb.Device;
const Endpoint = usb.Endpoint;
const SetupPacket = usb.SetupPacket;
const Error = usb.Error;

const CompletionCallback = *const fn (request: *UsbTransferRequest) void;

/// Specifies a transfer to be carried out asynchronously. This is
/// originally filled in by the caller, then used for tracking by the
/// channel interrupt handler
const UsbTransferRequest = struct {
    device: *Device,
    endpoint: *Endpoint,
    buffer: []u8, // caller-owned memory
    setup_packet: *SetupPacket, // only used in Control transfers

    completion_callback: CompletionCallback,
    completion_data: anyopaque, // caller-owned pointer

    status: Error,
    actual_size: usize,

    // the following members are private to the HCD
};
