pub const PowerResult = enum {
    unknown,
    failed,
    no_such_device,
    power_on,
    power_off,
};

/// VTable for power controller
pub const PowerController = struct {
    powerOn: *const fn (power_controller: *PowerController, power_domain: u32) PowerResult,
    powerOff: *const fn (power_controller: *PowerController, power_domain: u32) PowerResult,
    isPowered: *const fn (power_controller: *PowerController, power_domain: u32) PowerResult,
};
