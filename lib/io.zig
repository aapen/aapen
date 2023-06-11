//const std = @import("std");

//  const peripheral_base: u64 = 0xfe000000;   // RPi 4

const peripheral_base: u64 = 0x3f000000; // RPi 3
const gpfsel0: u64 = peripheral_base + 0x200000;
const gpset0: u64 = peripheral_base + 0x20001c;
const gpclr0: u64 = peripheral_base + 0x200028;
const gppuppdn0: u64 = peripheral_base + 0x2000e4;

const gpio_max_pin: u64 = 53;
const gpio_function_alt5: u64 = 2;

const pull_none: u64 = 0;

pub fn mmio_write(reg: *u64, val: u64) void {
    reg.* = val;
    //     std.debug.print("write: {x}", .{val});
    //     std.debug.print("to: {x}", .{reg});
}

pub fn mmio_read(reg: *volatile u64) u64 {
    return reg.*;
    //return reg.*;
    // std.debug.print("read: {x}", .{reg});
    // return 7717;
}

fn gpio_call(pin_number: u64, value: u64, base: u64, field_size: u64, field_max: u64) u64 {
    const one: u64 = 1;
    const field_mask: u64 = (one << @intCast(u6, field_size)) - 1;

    if (pin_number > field_max)
        return 0;

    if (value > field_mask)
        return 0;

    const num_fields: u64 = 32 / field_size;
    const reg: *volatile u64 = @intToPtr(*volatile u64, base + ((pin_number / num_fields) * 4));
    const shift: u64 = (pin_number % num_fields) * field_size;

    const curval = mmio_read(reg);
    curval &= ~(field_mask << shift);
    curval |= value << shift;
    mmio_write(reg, curval);

    return 1;
}

// pub fn main() callconv(.C) u32 {
//     //const p = peripheral_base;
//     var foo:u64 = 1234;
//     std.debug.print("foo: {d}\n", .{foo});
//     mmio_write(&foo, 777);
//     std.debug.print("foo: {d}\n", .{foo});
//     //std.debug.print("{x}\n", .{p});
//     var bar:u64 = mmio_read(&foo);
//     std.debug.print("bar: {d}\n", .{bar});
//     _ = gpio_call(7, 999, peripheral_base, 16, 64);
// }
