const std = @import("std");

extern fn __arch_atomic_fetch(atomic_val: *u64) u64;
extern fn __arch_atomic_fetch_add(atomic_val: *u64, addend: u64) u64;
extern fn __arch_atomic_add_fetch(atomic_val: *u64, addend: u64) u64;
extern fn __arch_atomic_fetch_sub(atomic_val: *u64, subtrahend: u64) u64;
extern fn __arch_atomic_sub_fetch(atomic_val: *u64, subtrahend: u64) u64;

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
