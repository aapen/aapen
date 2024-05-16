const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const HCI = root.HAL.USBHCI;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const schedule = @import("../schedule.zig");

const core = @import("core.zig");
const hub = @import("hub.zig");
const transfer = @import("transfer.zig");
const spec = @import("spec.zig");
const usb = @import("../usb.zig");

var allocator: Allocator = undefined;

pub fn init(alloc: Allocator) void {
    log = Logger.init("usbe", .debug);
    allocator = alloc;
}

// Make space that is guaranteed to be aligned correctly.
const REQUEST_BUFFER_LEN = 512;
var ep0_request_buffer: [hub.MAX_HUBS][REQUEST_BUFFER_LEN]u8 align(HCI.DMA_ALIGNMENT) = undefined;
var setup_buffer: [hub.MAX_HUBS][hub.MAX_INTERFACES]transfer.SetupPacket align(HCI.DMA_ALIGNMENT) = undefined;

pub fn later(port: *hub.HubPort) !void {
    log.debug(@src(), "spawning thread to enumerate asynchronously", .{});
    _ = try schedule.spawn(enumerate, "hub enumerate", port);
}

pub fn enumerate(args: *anyopaque) void {
    var port: *hub.HubPort = @ptrCast(@alignCast(args));

    initializePort(port) catch |err| {
        log.err(@src(), "failed to schedule port enumeration: {}", .{err});
    };
}

fn initializePort(port: *hub.HubPort) !void {
    const setup = &port.setup;

    const ep0_req_buf: []u8 = &ep0_request_buffer[port.parent.index];
    const ep_desc: *spec.EndpointDescriptor = &port.ep0;

    // Initialize the port's ep0, since we need it for the early control transfers
    ep_desc.endpoint_address = 0x00;
    ep_desc.descriptor_type = spec.USB_DESCRIPTOR_TYPE_ENDPOINT;
    ep_desc.attributes = spec.USB_ENDPOINT_TYPE_CONTROL;
    ep_desc.max_packet_size = defaultMps(port.speed);
    ep_desc.interval = 0;
    ep_desc.length = 7;

    port.device_address = 0;

    // First, read the first 8 bytes of the device descriptor, to find
    // out the real MPS
    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = @as(u16, spec.USB_DESCRIPTOR_TYPE_DEVICE) << 8;
    setup.index = 0;
    setup.data_size = 8;

    log.debug(@src(), "read device descriptor", .{});

    _ = try core.controlTransfer(port, setup, ep0_req_buf);

    try parseDeviceDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), 8);

    var ep_mps: u16 = 0;

    if (port.device_desc.usb_standard_compliance >= spec.usb3_0) {
        ep_mps = @as(u16, 1) << @truncate(port.device_desc.max_packet_size);
    } else {
        ep_mps = port.device_desc.max_packet_size;
    }

    ep_desc.max_packet_size = ep_mps;

    const dev_addr = try usb.addressAllocate();
    errdefer usb.addressFree(dev_addr);

    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT;
    setup.request = spec.USB_REQUEST_SET_ADDRESS;
    setup.value = dev_addr;
    setup.index = 0;
    setup.data_size = 0;

    log.debug(@src(), "assigning the device to use address {d}", .{dev_addr});

    _ = try core.controlTransfer(port, setup, null);

    try schedule.sleep(2);

    // reconfigure the port and its endpoint for the real address
    port.device_address = dev_addr;

    // read the full device descriptor
    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = @as(u16, spec.USB_DESCRIPTOR_TYPE_DEVICE) << 8;
    setup.index = 0;
    setup.data_size = spec.DeviceDescriptor.STANDARD_LENGTH;

    log.debug(@src(), "read full device descriptor from {d}", .{dev_addr});

    _ = try core.controlTransfer(port, setup, ep0_req_buf);
    try parseDeviceDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), spec.DeviceDescriptor.STANDARD_LENGTH);

    var config_index: u8 = 0;

    // read the first part of the config descriptor
    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = (@as(u16, spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8) | config_index;
    setup.index = 0;
    setup.data_size = 9;

    log.debug(@src(), "read config descriptor (short)", .{});

    _ = try core.controlTransfer(port, setup, ep0_req_buf);

    try parseConfigDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), spec.ConfigurationDescriptor.STANDARD_LENGTH);

    const total_length: u16 = port.config_desc.total_length;

    if (total_length > REQUEST_BUFFER_LEN) {
        log.err(@src(), "config descriptor total length is {d}, buffer is {d} bytes", .{ total_length, REQUEST_BUFFER_LEN });
    }

    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = (@as(u16, 1) << 8) | config_index;
    setup.index = 0;
    setup.data_size = total_length;

    log.debug(@src(), "read full config descriptor ({d} bytes)", .{total_length});

    _ = try core.controlTransfer(port, setup, ep0_req_buf);

    try parseConfigDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), total_length);

    // stash the raw config descriptor, some class drivers need it
    port.raw_config_descriptor = try allocator.alloc(u8, total_length);
    errdefer allocator.free(port.raw_config_descriptor);

    @memcpy(port.raw_config_descriptor, ep0_req_buf);

    // show some device diagnostics
    dumpDeviceString("Manufacturer", port, setup, port.device_desc.manufacturer_name);
    dumpDeviceString("Product", port, setup, port.device_desc.product_name);
    dumpDeviceString("Serial", port, setup, port.device_desc.serial_number);

    // choose config 1
    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_OUT;
    setup.request = spec.USB_REQUEST_SET_CONFIGURATION;
    setup.value = port.config_desc.configuration_value;
    setup.index = 0;
    setup.data_size = 0;

    log.debug(@src(), "select configuration {d}", .{port.config_desc.configuration_value});

    _ = try core.controlTransfer(port, setup, null);
}

fn defaultMps(speed: u8) spec.PacketSize {
    return switch (speed) {
        spec.USB_SPEED_LOW => 8,
        spec.USB_SPEED_FULL, spec.USB_SPEED_HIGH => 64,
        spec.USB_SPEED_SUPER, spec.USB_SPEED_SUPER_PLUS => 512,
        else => 64,
    };
}

fn dumpDeviceString(label: []const u8, port: *hub.HubPort, setup: *transfer.SetupPacket, index: spec.StringIndex) void {
    var desc: spec.StringDescriptor = undefined;

    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = @as(u16, 1) << spec.USB_DESCRIPTOR_TYPE_STRING | index;
    setup.index = 0x0409; // english
    setup.data_size = @sizeOf(spec.StringDescriptor);

    _ = core.controlTransfer(port, setup, std.mem.asBytes(&desc)) catch |err| {
        log.err(@src(), "Failed to get string descriptor {d}: {}", .{ index, err });
    };

    var buf: [256]u8 = undefined;
    const str = desc.intoSlice(&buf);
    log.info(@src(), "{s}: '{s}'", .{ label, str });
}

fn parseDeviceDescriptor(port: *hub.HubPort, desc: *spec.DeviceDescriptor, length: usize) !void {
    if (desc.length != spec.DeviceDescriptor.STANDARD_LENGTH) {
        return error.InvalidData;
    }

    if (desc.descriptor_type != spec.USB_DESCRIPTOR_TYPE_DEVICE) {
        return error.InvalidData;
    }

    if (length < 8) {
        return;
    }

    log.debug(@src(), "Device Descriptor:", .{});
    log.debug(@src(), "bLength: 0x{x:0>2}           ", .{desc.length});
    log.debug(@src(), "bDescriptorType: 0x{x:0>2}   ", .{desc.descriptor_type});
    log.debug(@src(), "bcdUSB: 0x{x:0>4}            ", .{desc.usb_standard_compliance});
    log.debug(@src(), "bDeviceClass: 0x{x:0>2}      ", .{desc.device_class});
    log.debug(@src(), "bDeviceSubClass: 0x{x:0>2}   ", .{desc.device_subclass});
    log.debug(@src(), "bDeviceProtocol: 0x{x:0>2}   ", .{desc.device_protocol});
    log.debug(@src(), "bMaxPacketSize0: 0x{x:0>2}   ", .{desc.max_packet_size});
    log.debug(@src(), "idVendor: 0x{x:0>4}          ", .{desc.vendor});
    log.debug(@src(), "idProduct: 0x{x:0>4}         ", .{desc.product});
    log.debug(@src(), "bcdDevice: 0x{x:0>4}         ", .{desc.device_release});
    log.debug(@src(), "iManufacturer: 0x{x:0>2}     ", .{desc.manufacturer_name});
    log.debug(@src(), "iProduct: 0x{x:0>2}          ", .{desc.product_name});
    log.debug(@src(), "iSerialNumber: 0x{x:0>2}     ", .{desc.serial_number});
    log.debug(@src(), "bNumConfigurations: 0x{x:0>2}", .{desc.configuration_count});

    port.device_desc.length = desc.length;
    port.device_desc.descriptor_type = desc.descriptor_type;
    port.device_desc.usb_standard_compliance = desc.usb_standard_compliance;
    port.device_desc.device_class = desc.device_class;
    port.device_desc.device_subclass = desc.device_subclass;
    port.device_desc.device_protocol = desc.device_protocol;
    port.device_desc.max_packet_size = desc.max_packet_size;
    port.device_desc.vendor = desc.vendor;
    port.device_desc.product = desc.product;
    port.device_desc.device_release = desc.device_release;
    port.device_desc.manufacturer_name = desc.manufacturer_name;
    port.device_desc.product_name = desc.product_name;
    port.device_desc.serial_number = desc.serial_number;
    port.device_desc.configuration_count = desc.configuration_count;
}

fn parseConfigDescriptor(port: *hub.HubPort, desc: *spec.ConfigurationDescriptor, length: usize) !void {
    if (desc.length != spec.ConfigurationDescriptor.STANDARD_LENGTH) {
        return error.InvalidData;
    }

    if (desc.descriptor_type != spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) {
        return error.InvalidData;
    }

    if (length <= spec.ConfigurationDescriptor.STANDARD_LENGTH) {
        return;
    }

    port.config_desc.length = desc.length;
    port.config_desc.descriptor_type = desc.descriptor_type;
    port.config_desc.total_length = desc.total_length;
    port.config_desc.interface_count = desc.interface_count;
    port.config_desc.configuration_value = desc.configuration_value;
    port.config_desc.configuration = desc.configuration;
    port.config_desc.attributes = desc.attributes;
    port.config_desc.power_max = desc.power_max;

    var srcptr: [*]u8 = @ptrCast(desc);
    var src_len: usize = spec.ConfigurationDescriptor.STANDARD_LENGTH;

    // initialize the destination data structure
    @memset(port.interfaces[0..hub.MAX_INTERFACES], hub.Interface{});

    // step past the ConfigurationDescriptor bytes
    srcptr += src_len;

    var cur_iface: usize = 0;
    _ = cur_iface;
    var cur_alt_setting: usize = 0;
    _ = cur_alt_setting;
    var cur_ep_num: usize = 0;
    _ = cur_ep_num;
    var cur_ep: usize = 0;
    _ = cur_ep;
}
