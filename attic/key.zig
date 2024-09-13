pub const Keycode = u16;
pub const KEYCODE_MAX: Keycode = 0xffff;

pub usingnamespace @import("ascii.zig");

// zig fmt: off
pub const MOD_SHIFT            : Keycode = 0x100;
pub const MOD_CONTROL          : Keycode = 0x200;
pub const MOD_ALT              : Keycode = 0x400;
pub const MOD_HYPER            : Keycode = 0x800;

pub const UP_ARROW             : Keycode = 0x80;
pub const DOWN_ARROW           : Keycode = 0x81;
pub const LEFT_ARROW           : Keycode = 0x82;
pub const RIGHT_ARROW          : Keycode = 0x83;
pub const HOME                 : Keycode = 0x84;
pub const END                  : Keycode = 0x85;
pub const F1                   : Keycode = 0x90;
pub const F2                   : Keycode = 0x91;
pub const F3                   : Keycode = 0x92;
pub const F4                   : Keycode = 0x93;
pub const F5                   : Keycode = 0x94;
pub const F6                   : Keycode = 0x95;
pub const F7                   : Keycode = 0x96;
pub const F8                   : Keycode = 0x97;
pub const F9                   : Keycode = 0x98;
pub const F10                  : Keycode = 0x99;
pub const F11                  : Keycode = 0x9a;
pub const F12                  : Keycode = 0x9b;
pub const SHIFT_F1             : Keycode = 0xa0;
pub const SHIFT_F2             : Keycode = 0xa1;
pub const SHIFT_F3             : Keycode = 0xa2;
pub const SHIFT_F4             : Keycode = 0xa3;
pub const SHIFT_F5             : Keycode = 0xa4;
pub const SHIFT_F6             : Keycode = 0xa5;
pub const SHIFT_F7             : Keycode = 0xa6;
pub const SHIFT_F8             : Keycode = 0xa7;
pub const SHIFT_F9             : Keycode = 0xa8;
pub const SHIFT_F10            : Keycode = 0xa9;
pub const SHIFT_F11            : Keycode = 0xaa;
pub const SHIFT_F12            : Keycode = 0xab;

pub const FIRST_UNASSIGNED_KEY : Keycode = 0xac;
