const std = @import("std");
const root = @import("root");
const kprint = root.kprint;

const hal = @import("../hal.zig");
const InterruptController = hal.interfaces.InterruptController;
const PowerController = hal.interfaces.PowerController;

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const mailbox = @import("bcm_mailbox.zig");
const memory_map = @import("../hal/raspi3/memory_map.zig");

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

// ----------------------------------------------------------------------
// Host channel registers
// ----------------------------------------------------------------------

const HostChannelRegisters = extern struct {
    hcchar: u32 = 0,
    hcsplt: u32 = 0,
    hcint: u32 = 0,
    hcintmsk: u32 = 0,
    hctsiz: u32 = 0,
    hcdma: u32 = 0,
    _reserved: u32 = 0,
    hcdmab: u32 = 0,
};

const HostRegisters = extern struct {
    hcfg: u32 = 0,
    hfir: u32 = 0,
    hfnum: u32 = 0,
    _unused_padding: u32 = 0,
    hptxsts: u32 = 0,
    haint: u32 = 0,
    haintmsk: u32 = 0,
    hflbaddr: u32 = 0,
};

const CoreRegisters = extern struct {
    gotgctl: u32 = 0,
    gotgint: u32 = 0,
    gahbcfg: u32 = 0,
    gusbcfg: u32 = 0,
    grstctl: u32 = 0,
    gintsts: u32 = 0,
    gintmsk: u32 = 0,
    grxstsr: u32 = 0,
    grxstsp: u32 = 0,
    grxfsiz: u32 = 0,
    gnptxfsiz: u32 = 0,
    gnptxsts: u32 = 0,
    gi2cctl: u32 = 0,
    gpvndctl: u32 = 0,
    ggpio: u32 = 0,
    guid: u32 = 0,
    gsnpsid: u32 = 0,
    ghwcfg1: u32 = 0,
    ghwcfg2: u32 = 0,
    ghwcfg3: u32 = 0,
    ghwcfg4: u32 = 0,
    glpmcfg: u32 = 0,
    _pad_0x58_0x9c: [42]u32,
    hptxfsiz: u32 = 0,
    dptxfsiz_dieptxf: [15]u32,
    _pad_0x140_0x3fc: [176]u32,
    host_regs: u32 = 0,
    _pad_0x420_0x43c: [8]u32,
    hprt0: u32 = 0,
    _pad_0x444_0x4fc: [47]u32,
    hc_regs: [16]u32,
    _pad_0x700_0xe00: [448]u32,
    pcgcctl: u32 = 0,
};

// snpsid = readl(&regs->gsnpsid);
// dev_info(dev, "Core Release: %x.%03x\n",
// 	 snpsid >> 12 & 0xf, snpsid & 0xfff);

// if ((snpsid & DWC2_SNPSID_DEVID_MASK) != DWC2_SNPSID_DEVID_VER_2xx &&
//     (snpsid & DWC2_SNPSID_DEVID_MASK) != DWC2_SNPSID_DEVID_VER_3xx) {
// 	dev_info(dev, "SNPSID invalid (not DWC2 OTG device): %08x\n",
// 		 snpsid);

pub const UsbController = struct {
    interface: hal.interfaces.USB = undefined,

    core_registers: *volatile CoreRegisters = undefined,
    intc: *InterruptController = undefined,
    translations: *AddressTranslations = undefined,
    power_controller: *PowerController = undefined,

    // TODO initialize the clock
    // TODO initialize the phy interface
    pub fn init(
        self: *UsbController,
        base: u64,
        interrupt_controller: *InterruptController,
        translations: *AddressTranslations,
        power_controller: *PowerController,
    ) void {
        self.interface = .{
            .powerOn = powerOn,
            .powerOff = powerOff,
        };
        self.core_registers = @ptrFromInt(base);
        self.intc = interrupt_controller;
        self.translations = translations;
        self.power_controller = power_controller;
    }

    pub fn usb(self: *UsbController) *hal.interfaces.USB {
        return &self.interface;
    }

    fn powerOn(intf: *hal.interfaces.USB) void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const usb_power_result = self.power_controller.powerOn(self.power_controller, 3);
        kprint("\n{s:>20}: {s}\n", .{ "Power on USB", @tagName(usb_power_result) });
    }

    fn powerOff(intf: *hal.interfaces.USB) void {
        const self = @fieldParentPtr(@This(), "interface", intf);
        const usb_power_result = self.power_controller.powerOff(self.power_controller, 3);
        kprint("\n{s:>20}: {s}\n", .{ "Power on USB", @tagName(usb_power_result) });
    }
};
