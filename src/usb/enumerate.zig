const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root");
const HCI = root.HAL.USBHCI;

const Logger = @import("../logger.zig");
var log: *Logger = undefined;

const schedule = @import("../schedule.zig");

const class = @import("class.zig");
const core = @import("core.zig");
const hub = @import("hub.zig");
const transfer = @import("transfer.zig");
const spec = @import("spec.zig");
const status = @import("status.zig");
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

    log.sliceDump(@src(), ep0_req_buf[0..8]);

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

    log.sliceDump(@src(), ep0_req_buf[0..spec.DeviceDescriptor.STANDARD_LENGTH]);

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

    log.sliceDump(@src(), ep0_req_buf[0..9]);

    try parseConfigDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), spec.ConfigurationDescriptor.STANDARD_LENGTH);

    const total_length: u16 = port.config_desc.total_length;

    if (total_length > REQUEST_BUFFER_LEN) {
        log.err(@src(), "config descriptor total length is {d}, buffer is {d} bytes", .{ total_length, REQUEST_BUFFER_LEN });
    }

    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = (@as(u16, spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) << 8) | config_index;
    setup.index = 0;
    setup.data_size = total_length;

    log.debug(@src(), "read full config descriptor ({d} bytes)", .{total_length});

    _ = try core.controlTransfer(port, setup, ep0_req_buf);

    log.sliceDump(@src(), ep0_req_buf[0..total_length]);

    try parseConfigDescriptor(port, @ptrCast(@alignCast(ep0_req_buf)), total_length);

    // stash the raw config descriptor, some class drivers need it
    port.raw_config_descriptor = try allocator.alloc(u8, total_length);
    errdefer allocator.free(port.raw_config_descriptor);

    @memcpy(port.raw_config_descriptor, ep0_req_buf[0..total_length]);

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

    // find a driver for each supported interface
    for (0..port.config_desc.interface_count) |iface| {
        const intf_desc = &port.interfaces[iface].alternate[0].interface_descriptor;

        if (class.findDriver(intf_desc.interface_class, intf_desc.interface_subclass, intf_desc.interface_protocol, port.device_desc.vendor, port.device_desc.product)) |drv| {
            port.interfaces[iface].class_driver = drv;
            log.info(@src(), "Loading {s} class driver", .{drv.name});
        } else {
            log.err(@src(), "no driver for interface {d}-{d}-{d}", .{
                intf_desc.interface_class,
                intf_desc.interface_subclass,
                intf_desc.interface_protocol,
            });
        }
    }
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
    var desc: spec.StringDescriptor align(HCI.DMA_ALIGNMENT) = undefined;

    setup.request_type = spec.USB_REQUEST_TYPE_DEVICE_STANDARD_IN;
    setup.request = spec.USB_REQUEST_GET_DESCRIPTOR;
    setup.value = @as(u16, spec.USB_DESCRIPTOR_TYPE_STRING) << 8 | index;
    setup.index = 0x0409; // english
    setup.data_size = @sizeOf(spec.StringDescriptor);

    _ = core.controlTransfer(port, setup, std.mem.asBytes(&desc)) catch |err| {
        log.err(@src(), "Failed to get string descriptor {d}: {}", .{ index, err });
        return;
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

fn parseConfigDescriptor(port: *hub.HubPort, desc: *spec.ConfigurationDescriptor, expected_length: usize) !void {
    if (desc.length != spec.ConfigurationDescriptor.STANDARD_LENGTH) {
        log.err(@src(), "descriptor length {d}, expected {d}", .{ desc.length, spec.ConfigurationDescriptor.STANDARD_LENGTH });
        return error.InvalidData;
    }

    if (desc.descriptor_type != spec.USB_DESCRIPTOR_TYPE_CONFIGURATION) {
        log.err(@src(), "descriptor type {d}, expected {d}", .{ desc.descriptor_type, spec.USB_DESCRIPTOR_TYPE_CONFIGURATION });
        return error.InvalidData;
    }

    if (expected_length < spec.ConfigurationDescriptor.STANDARD_LENGTH) {
        log.err(@src(), "caller requested {d} bytes, but minimum is {d}", .{ expected_length, spec.ConfigurationDescriptor.STANDARD_LENGTH });
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
    var bytes_consumed: usize = spec.ConfigurationDescriptor.STANDARD_LENGTH;

    // initialize the destination data structure
    @memset(port.interfaces[0..hub.MAX_INTERFACES], hub.Interface{});

    // step past the ConfigurationDescriptor bytes
    srcptr += bytes_consumed;

    var cur_iface: u8 = 0;
    var cur_alt_setting: u8 = 0;
    var cur_ep_num: u8 = 0;
    var cur_ep: u8 = 0;

    while (srcptr[0] != 0 and bytes_consumed <= expected_length) {
        const desc_len = srcptr[0];
        const desc_type = srcptr[1];

        switch (desc_type) {
            usb.USB_DESCRIPTOR_TYPE_INTERFACE => {
                const intf_desc: *align(1) spec.InterfaceDescriptor = std.mem.bytesAsValue(spec.InterfaceDescriptor, srcptr[0..@sizeOf(spec.InterfaceDescriptor)]);
                cur_iface = intf_desc.interface_number;
                cur_alt_setting = intf_desc.alternate_setting;
                cur_ep_num = intf_desc.endpoint_count;
                cur_ep = 0;

                if (cur_iface > hub.MAX_INTERFACES - 1) {
                    log.err(@src(), "interface overflow", .{});
                    return error.InitializationFailure;
                }

                if (cur_alt_setting > hub.MAX_INTERFACE_ALTERNATES - 1) {
                    log.err(@src(), "interface alternate setting overflow", .{});
                    return error.InitializationFailure;
                }

                if (cur_ep_num > hub.MAX_ENDPOINTS - 1) {
                    log.err(@src(), "endpoint overflow", .{});
                    return error.InitializationFailure;
                }

                log.debug(@src(), "Interface Descriptor:         ", .{});
                log.debug(@src(), "bLength: 0x{x:0>2}            ", .{intf_desc.length});
                log.debug(@src(), "bDescriptorType: 0x{x:0>2}    ", .{intf_desc.descriptor_type});
                log.debug(@src(), "bInterfaceNumber: 0x{x:0>2}   ", .{intf_desc.interface_number});
                log.debug(@src(), "bAlternateSetting: 0x{x:0>2}  ", .{intf_desc.alternate_setting});
                log.debug(@src(), "bNumEndpoints: 0x{x:0>2}      ", .{intf_desc.endpoint_count});
                log.debug(@src(), "bInterfaceClass: 0x{x:0>2}    ", .{intf_desc.interface_class});
                log.debug(@src(), "bInterfaceSubClass: 0x{x:0>2} ", .{intf_desc.interface_subclass});
                log.debug(@src(), "bInterfaceProtocol: 0x{x:0>2} ", .{intf_desc.interface_protocol});
                log.debug(@src(), "iInterface: 0x{x:0>2}         ", .{intf_desc.interface_number});

                port.interfaces[cur_iface].alternate[cur_alt_setting].interface_descriptor = intf_desc.*;
                port.interfaces[cur_iface].altsetting_count = cur_alt_setting + 1;
            },
            usb.USB_DESCRIPTOR_TYPE_ENDPOINT => {
                //                const ep_desc: *spec.EndpointDescriptor = @ptrCast(@alignCast(srcptr));
                const ep_desc: *align(1) spec.EndpointDescriptor = std.mem.bytesAsValue(spec.EndpointDescriptor, srcptr[0..@sizeOf(spec.EndpointDescriptor)]);
                port.interfaces[cur_iface].alternate[cur_alt_setting].ep[cur_ep].ep_desc = ep_desc.*;
                cur_ep += 1;
            },
            usb.USB_DESCRIPTOR_TYPE_HID => {
                // TODO - something reasonable
                //                const hid_descriptor: *spec.HidDescriptor = @ptrCast(@alignCast(srcptr));
                const hid_descriptor: *align(1) spec.HidDescriptor = std.mem.bytesAsValue(spec.HidDescriptor, srcptr[0..@sizeOf(spec.HidDescriptor)]);
                log.info(@src(), "hid descriptor found: {any}", .{hid_descriptor.*});
            },
            else => {},
        }

        // advance to next descriptor
        srcptr += desc_len;
        bytes_consumed += srcptr[0];
    }
}
