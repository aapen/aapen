const helpers = @import("helpers.zig");
const expect = helpers.expect;
const expectEqual = helpers.expectEqual;
const expectError = helpers.expectError;

const transfer = @import("../usb/transfer.zig");
const SetupPacket = transfer.SetupPacket;
const Transfer = transfer.Transfer;

pub fn testBody() !void {
    assertControlTransferStartsWithToken();
    assertControlTransferWithDataHasThreePhases();
    assertControlTransferWithoutDataHasTwoPhases();
    assertCompletionHandlerCalledWhenTransferSucceeds();
    assertCompletionHandlerCalledWhenTransferFails();
}

fn assertControlTransferStartsWithToken() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = SetupPacket.init(.device, .standard, .device_to_host, 0x06, 0, 0, buffer_size);
    const xfer = Transfer.initControl(pkt, &buffer);

    expectEqual(Transfer.State.token, xfer.state);
}

fn assertControlTransferWithDataHasThreePhases() void {
    const buffer_size = 18;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = SetupPacket.init(.device, .standard, .device_to_host, 0x06, 0, 0, buffer_size);
    var xfer = Transfer.initControl(pkt, &buffer);

    expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.data, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.complete, xfer.state);
    expectEqual(Transfer.CompletionStatus.ok, xfer.status);
}

fn assertControlTransferWithoutDataHasTwoPhases() void {
    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = SetupPacket.init(.device, .standard, .host_to_device, 0x05, 1, 0, buffer_size);
    var xfer = Transfer.initControl(pkt, &buffer);

    expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.complete, xfer.state);
    expectEqual(Transfer.CompletionStatus.ok, xfer.status);
}

fn assertCompletionHandlerCalledWhenTransferSucceeds() void {
    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = SetupPacket.init(.device, .standard, .host_to_device, 0x05, 1, 0, buffer_size);
    var xfer = Transfer.initControl(pkt, &buffer);

    const Callback = struct {
        var was_called: bool = false;

        fn invoke(_: *Transfer) void {
            was_called = true;
        }
    };
    xfer.completion = &Callback.invoke;

    expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.complete, xfer.state);
    expectEqual(Transfer.CompletionStatus.ok, xfer.status);
    expect(Callback.was_called);
}

fn assertCompletionHandlerCalledWhenTransferFails() void {
    const buffer_size = 0;
    var buffer: [buffer_size]u8 = undefined;
    const pkt = SetupPacket.init(.device, .standard, .host_to_device, 0x05, 1, 0, buffer_size);
    var xfer = Transfer.initControl(pkt, &buffer);

    const Callback = struct {
        var was_called: bool = false;

        fn invoke(_: *Transfer) void {
            was_called = true;
        }
    };
    xfer.completion = &Callback.invoke;

    expectEqual(Transfer.State.token, xfer.state);

    xfer.transferCompleteTransaction(.ok);

    expectEqual(Transfer.State.handshake, xfer.state);

    xfer.transferCompleteTransaction(.timeout);

    expectEqual(Transfer.State.complete, xfer.state);
    expectEqual(Transfer.CompletionStatus.timeout, xfer.status);
    expect(Callback.was_called);
}
