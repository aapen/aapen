# Synchronization primitives

## Critical section

### Construction

None.

### Operations

`criticalEnter(InterruptLevel)` - enter a critical section, allowing only interrupts at or above the target interrupt level (which must be one of `Task`, `IRQ`, or `FIQ`).

`criticalLeave(InterruptLevel)` - exit a critical section, restoring the allowed interrupts from before entering it.

Critical sections are reentrant, but enters and leaves must balance.

## Spinlock

### Construction

`Spinlock.init(name: [] const u8, enabled: bool) Spinlock`

Returns the spinlock as a value. Caller must copy the value.

Can be used statically as in:

`var my_lock: Spinlock = Spinlock.init("my name", true)`

If `enabled` is false, then all attempts to acquire or release will return immediately as a no-op. When ready, set `lock.enabled` to true in order for future acquire and release calls to work.

### Operations

`Spinlock.acquire(*Spinlock) void` - Atomically updates the lock. Will block until able to acquire the lock. On aarch64, uses `ldaxr` for exclusive load and `stxr` for exclusive store. Despite the name spinlock, it uses `wfe` to go idle until an event wakes the PE.

`Spinlock.release(*Spinlock) void` - Atomically releases the lock. Will not block. Uses `stlr` for store-with-notify, which sends the event needed to wake the PE.

These are usually paired like:

```
lock.acquire();
defer lock.release();
```

Spinlocks are _not_ reentrant. Deadlock will result if code tries to acquire a lock that it already holds.

## Semaphore

### Construction

`Semaphore.init(initial_value: u64) Semaphore`

Returns the semaphore structure as a value. Caller must copy the value.

Can be used statically as in:

`var my_semaphore: Semaphore = Semaphore.init(10);`

### Operations

`Semaphore.signal(*Semaphore) void` - Increments the semaphore. Uses `ldaxr` and `stlxr` for atomic load and store with exclusivity. Sends an event with `sev` to wake up waiters.

`Semaphore.wait(*Semaphore) void` - If the semaphore is positive, decrement the count and return immediately. If semaphore is zero, use `wfe` to wait for another thread to increment it.

`Semaphore.count(*Semaphore) u64` - Get the "current" value of the semaphore. Beware that this can change the instant after you look at it.

