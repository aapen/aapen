const std = @import("std");

const root = @import("root");
const HCI = root.HAL.USBHCI;

const arch = @import("../architecture.zig");
const cpu = arch.cpu;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const semaphore = @import("../semaphore.zig");
const SID = semaphore.SID;

const synchronize = @import("../synchronize.zig");
const TicketLock = synchronize.TicketLock;

const device = @import("device.zig");
const spec = @import("spec.zig");
const status = @import("status.zig");
const Error = status.Error;
const transfer = @import("transfer.zig");

// ----------------------------------------------------------------------
// Lifecycle
// ----------------------------------------------------------------------
var allocator: std.mem.Allocator = undefined;

pub fn initCore(alloc: std.mem.Allocator) void {
    log = Logger.init("usb_core", .info);

    allocator = alloc;
}

// ----------------------------------------------------------------------
// Transfer handling
// ----------------------------------------------------------------------

// submit a transfer for asynchronous processing
pub fn transferSubmit(req: *transfer.TransferRequest) !void {
    const im = cpu.disable();
    defer cpu.restore(im);

    // check if the device is being detached or has not been configured
    if (req.device) |dev| {
        switch (dev.state) {
            .detaching => return Error.DeviceDetaching,
            .unconfigured => return Error.DeviceUnconfigured,
            inline else => {},
        }
    } else {
        return Error.NoDevice;
    }

    // TODO track how many requests are pending for a device
    try root.hal.usb_hci.perform(req);
}

fn controlMessageDone(xfer: *transfer.TransferRequest) void {
    log.debug(@src(), "signalling completion semaphore {d}", .{xfer.semaphore.?});
    semaphore.signal(xfer.semaphore.?) catch {
        log.err(@src(), "failed to signal semaphore {?d} on completion of control msg", .{xfer.semaphore});
    };
}

// ----------------------------------------------------------------------
// Specific transfers
// ----------------------------------------------------------------------
pub fn controlMessage(
    dev: *device.Device,
    req_code: u8,
    req_type: u8,
    val: u16,
    index: u16,
    data: []u8,
) !transfer.TransferRequest.CompletionStatus {
    const sem: SID = try semaphore.create(0);
    defer semaphore.free(sem) catch |err| {
        log.err(@src(), "semaphore {d} free error: {any}", .{ sem, err });
    };

    var req: *transfer.TransferRequest = try transfer.TransferRequest.create(allocator, dev, .{
        .request_type = req_type,
        .request = req_code,
        .value = val,
        .index = index,
        .data_size = @truncate(data.len),
    }, data);
    defer req.deinit(allocator);

    req.completion = controlMessageDone;
    req.semaphore = sem;
    try transferSubmit(req);

    // TODO add the ability to time out
    semaphore.wait(sem) catch |err| {
        log.err(@src(), "semaphore {d} wait error: {any}", .{ sem, err });
    };

    if (req.status == .ok and req.actual_size != data.len) {
        return .incomplete;
    } else {
        return req.status;
    }
}

pub fn deviceDescriptorRead(dev: *device.Device, maxlen: spec.TransferBytes) !void {
    log.debug(@src(), "[{d}:{d}] read device descriptor (maxlen {d} bytes)", .{ dev.address, 0, maxlen });
    const buffer: []u8 = std.mem.asBytes(&dev.device_descriptor);
    const readlen = @min(maxlen, buffer.len);
    const result = try controlMessage(
        dev,
        spec.USB_REQUEST_GET_DESCRIPTOR, // req
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN, // req type
        @as(u16, spec.USB_DESCRIPTOR_TYPE_DEVICE) << 8, // value
        spec.USB_LANGID_NONE, // index
        buffer[0..readlen], // data
    );
    if (result == .failed) {
        return Error.TransferFailed;
    }
}

pub fn deviceSetAddress(dev: *device.Device, address: spec.DeviceAddress) !void {
    log.debug(@src(), "[{d}:{d}] set address {d}", .{ dev.address, 0, address });

    const result = try controlMessage(
        dev,
        spec.USB_REQUEST_SET_ADDRESS, // req
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT, // req type
        address, // value
        0, // index (not used for this transfer)
        &.{}, // data (not used for this transfer)
    );

    if (result == .failed) {
        return Error.TransferFailed;
    }

    dev.address = address;
}

pub fn deviceConfigurationDescriptorRead(dev: *device.Device) !void {
    log.debug(@src(), "[{d}:{d}] configuration descriptor read", .{ dev.address, 0 });
    // first transfer returns the configuration descriptor which
    // includes the total length of the whole configuration tree
    var desc: spec.ConfigurationDescriptor = undefined;

    const result = try controlMessage(
        dev,
        spec.USB_REQUEST_GET_DESCRIPTOR,
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN, // req type
        @as(u16, spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8, // value
        0, // index
        std.mem.asBytes(&desc),
    );

    if (result != .ok) {
        log.debug(@src(), "configuration descriptor read, first read result {s}", .{@tagName(result)});
        return Error.TransferFailed;
    }

    // now allocate enough space for the whole configuration (which
    // includes the interface descriptors and endpoint descriptors)
    const buffer_size = desc.total_length;
    const configuration: []u8 = try allocator.alloc(u8, buffer_size);
    defer allocator.free(configuration);

    const result2 = try controlMessage(
        dev,
        spec.USB_REQUEST_GET_DESCRIPTOR, // req
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN, // req type
        @as(u16, spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8, // value
        0, // index
        configuration,
    );
    if (result2 != .ok) {
        log.debug(@src(), "configuration descriptor read part 2, second read result {s}", .{@tagName(result2)});
        return Error.TransferFailed;
    }

    dev.configuration = try device.DeviceConfiguration.initFromBytes(allocator, configuration);
    log.debug(@src(), "{any}", .{dev.configuration});
}

pub fn deviceSetConfiguration(dev: *device.Device, use_config: u8) !void {
    log.debug(@src(), "[{d}:{d}] set configuration {d}", .{ dev.address, 0, use_config });

    _ = try controlMessage(
        dev,
        spec.USB_REQUEST_SET_CONFIGURATION, // req
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT, // req type
        use_config, // value
        0, // index (not used for this transfer)
        &.{}, // data (not used for this transfer)
    );
}

pub fn deviceGetStringDescriptor(dev: *device.Device, index: spec.StringIndex, lang_id: spec.LangId, buffer: []u8) !void {
    log.debug(@src(), "[{d}:{d}] get string descriptor {d}", .{ dev.address, 0, index });

    _ = try controlMessage(
        dev,
        spec.USB_REQUEST_GET_DESCRIPTOR, // req
        spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN, // req type
        @as(u16, spec.USB_DESCRIPTOR_TYPE_STRING) << 8 | index,
        lang_id,
        buffer,
    );
}
