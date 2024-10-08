const std = @import("std");

extern fn __arch_atomic_fetch(atomic_val: *u64) u64;
extern fn __arch_atomic_fetch_add(atomic_val: *u64, addend: u64) u64;
extern fn __arch_atomic_add_fetch(atomic_val: *u64, addend: u64) u64;
extern fn __arch_atomic_fetch_sub(atomic_val: *u64, subtrahend: u64) u64;
extern fn __arch_atomic_sub_fetch(atomic_val: *u64, subtrahend: u64) u64;
extern fn __arch_atomic_reset(atomic_val: *u64, new_value: u64) u64;

extern fn __arch_atomic_fetch_i16(atomic_val: *i16) i16;
extern fn __arch_atomic_fetch_add_i16(atomic_val: *i16, addend: i16) i16;
extern fn __arch_atomic_add_fetch_i16(atomic_val: *i16, addend: i16) i16;
extern fn __arch_atomic_fetch_sub_i16(atomic_val: *i16, subtrahend: i16) i16;
extern fn __arch_atomic_sub_fetch_i16(atomic_val: *i16, subtrahend: i16) i16;
extern fn __arch_atomic_reset_i16(atomic_val: *i16, new_value: i16) i16;

/// Atomically get value.
pub fn atomicFetch(atomic_val: *u64) u64 {
    return __arch_atomic_fetch(atomic_val);
}

/// Atomically add values. Returns the value _prior_ to adding.
pub fn atomicAdd(atomic_val: *u64, addend: u64) u64 {
    return __arch_atomic_fetch_add(atomic_val, addend);
}

/// Atomically add values. Returns the value _after_ adding
pub fn atomicAddFetch(atomic_val: *u64, addend: u64) u64 {
    return __arch_atomic_add_fetch(atomic_val, addend);
}

/// Atomically subtract a value. Returns the value _prior_ to subtraction.
pub fn atomicSub(atomic_val: *u64, subtrahend: u64) u64 {
    return __arch_atomic_fetch_sub(atomic_val, subtrahend);
}

/// Atomically subtract values. Returns the value _after_ subtraction
pub fn atomicSubFetch(atomic_val: *u64, subtrahend: u64) u64 {
    return __arch_atomic_sub_fetch(atomic_val, subtrahend);
}

/// Atomically increments the value, returns the value _prior_ to
/// incrementing.
pub inline fn atomicInc(atomic_val: *u64) u64 {
    return atomicAdd(atomic_val, 1);
}

/// Atomically decrement the value, returns the value _prior_ to
/// decrementing
pub inline fn atomicDec(atomic_val: *u64) u64 {
    return atomicSub(atomic_val, 1);
}

/// Atomically set the value, returns the value _prior_ to reset
pub inline fn atomicReset(atomic_val: *u64, new_value: u64) u64 {
    return __arch_atomic_reset(atomic_val, new_value);
}

/// Atomically get value.
pub fn atomicFetchi16(atomic_val: *i16) i16 {
    return __arch_atomic_fetch_i16(atomic_val);
}

/// Atomically add values. Returns the value _prior_ to adding.
pub fn atomicAddi16(atomic_val: *i16, addend: i16) i16 {
    return __arch_atomic_fetch_add_i16(atomic_val, addend);
}

/// Atomically add values. Returns the value _after_ adding
pub fn atomicAddFetchi16(atomic_val: *i16, addend: i16) i16 {
    return __arch_atomic_add_fetch_i16(atomic_val, addend);
}

/// Atomically subtract a value. Returns the value _prior_ to subtraction.
pub fn atomicSubi16(atomic_val: *i16, subtrahend: i16) i16 {
    return __arch_atomic_fetch_sub_i16(atomic_val, subtrahend);
}

/// Atomically subtract values. Returns the value _after_ subtraction
pub fn atomicSubFetchi16(atomic_val: *i16, subtrahend: i16) i16 {
    return __arch_atomic_sub_fetch_i16(atomic_val, subtrahend);
}

/// Atomically increments the value, returns the value _prior_ to
/// incrementing.
pub inline fn atomicInci16(atomic_val: *i16) i16 {
    return atomicAddi16(atomic_val, 1);
}

/// Atomically decrement the value, returns the value _prior_ to
/// decrementing
pub inline fn atomicDeci16(atomic_val: *i16) i16 {
    return atomicSubi16(atomic_val, 1);
}

/// Atomically set the value, returns the value _prior_ to reset
pub inline fn atomicReseti16(atomic_val: *i16, new_value: i16) i16 {
    return __arch_atomic_reset_i16(atomic_val, new_value);
}
