const std = @import("std");
const root = @import("root");
const kprint = root.kprint;

const hal = @import("../hal.zig");

const local_interrupt_controller = @import("arm_local_interrupt_controller.zig");
const bcm_power = @import("bcm_power.zig");

const memory = @import("../memory.zig");
const AddressTranslation = memory.AddressTranslation;
const AddressTranslations = memory.AddressTranslations;
const toChild = memory.toChild;
const toParent = memory.toParent;

const mailbox = @import("bcm_mailbox.zig");
const memory_map = @import("../hal/raspi3/memory_map.zig");

const usb_dwc_base = memory_map.peripheral_base + 0x980000;

// ----------------------------------------------------------------------
// Host controller registers
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
    gotgctl: u32 = 0, // 0x00
    gotgint: u32 = 0, // 0x04
    gahbcfg: u32 = 0, // 0x08
    gusbcfg: u32 = 0, // 0x0c
    grstctl: u32 = 0, // 0x10
    gintsts: u32 = 0, // 0x14
    gintmsk: u32 = 0, // 0x18
    grxstsr: u32 = 0, // 0x1c
    grxstsp: u32 = 0, // 0x20
    grxfsiz: u32 = 0, // 0x24
    gnptxfsiz: u32 = 0, // 0x28
    gnptxsts: u32 = 0, // 0x2c
    gi2cctl: u32 = 0, // 0x30
    gpvndctl: u32 = 0, // 0x34
    ggpio: u32 = 0, // 0x38
    guid: u32 = 0, // 0x3c
    gsnpsid: u32 = 0, // 0x40
    ghwcfg1: u32 = 0, // 0x44
    ghwcfg2: u32 = 0, // 0x48
    ghwcfg3: u32 = 0, // 0x4c
    ghwcfg4: u32 = 0, // 0x50
    glpmcfg: u32 = 0, // 0x54
    _pad_0x58_0x9c: [42]u32, // 0x58 .. 0xfc
    hptxfsiz: u32 = 0, // 0x100
    dptxfsiz_dieptxf: [15]u32, // 0x104 .. 0x140
    _pad_0x140_0x3fc: [176]u32, // 0x144 .. 0x3fc
    host_regs: HostRegisters, // 0x400
    _pad_0x420_0x43c: [8]u32,
    hprt0: u32 = 0, // 0x440
    _pad_0x444_0x4fc: [47]u32,
    hc_regs: HostChannelRegisters, // 0x500
    _pad_0x700_0xe00: [448]u32,
    pcgcctl: u32 = 0, // 0xe00
};

// snpsid = readl(&regs->gsnpsid);
// dev_info(dev, "Core Release: %x.%03x\n",
// 	 snpsid >> 12 & 0xf, snpsid & 0xfff);

// if ((snpsid & DWC2_SNPSID_DEVID_MASK) != DWC2_SNPSID_DEVID_VER_2xx &&
//     (snpsid & DWC2_SNPSID_DEVID_MASK) != DWC2_SNPSID_DEVID_VER_3xx) {
// 	dev_info(dev, "SNPSID invalid (not DWC2 OTG device): %08x\n",
// 		 snpsid);

pub const UsbController = struct {
    registers: *volatile CoreRegisters,
    intc: *const local_interrupt_controller.LocalInterruptController,
    translations: *const AddressTranslations,
    power_controller: *const bcm_power.BroadcomPowerController,

    pub fn powerOn(self: *const UsbController) void {
        const usb_power_result = self.power_controller.powerOn(3);
        kprint("\n{s:>20}: {s}\n", .{ "Power on USB", @tagName(usb_power_result) });
    }

    pub fn powerOff(self: *const UsbController) void {
        const usb_power_result = self.power_controller.powerOff(3);
        kprint("\n{s:>20}: {s}\n", .{ "Power on USB", @tagName(usb_power_result) });
    }

    pub fn hostControllerInitialize(self: *const UsbController) !void {
        self.powerOn();

        const id = self.registers.gsnpsid;
        const major = (id >> 12) & 0xf;
        const minor = id & 0xfff;

        kprint("   DWC2 OTG core rev: {x}.{x:0>3}\n", .{ major, minor });
    }
};
