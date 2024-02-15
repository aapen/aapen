# Synchronization primitives

## Disable/enable interrupts

### Operations

```
const im = cpu.disable();
defer cpu.restore(im);
```

Temporarily mask interrupts, then restore the previous mask on exit from the scope.

## TicketLock

### Construction

`TicketLock.init(name: [] const u8, enabled: bool) TicketLock`

Returns the spinlock as a value. Caller must copy the value.

Can be used statically as in:

`var my_lock: TicketLock = TicketLock.init("my name", true)`

If `enabled` is false, then all attempts to acquire or release will return immediately as a no-op. When ready, set `lock.enabled` to true in order for future acquire and release calls to work.

### Operations

`TicketLock.acquire(*TicketLock) void` - Atomically updates the lock. Will block until able to acquire the lock. On aarch64, uses `ldaxr` for exclusive load and `stxr` for exclusive store. Despite the name spinlock, it uses `wfe` to go idle until an event wakes the PE.

`TicketLock.release(*TicketLock) void` - Atomically releases the lock. Will not block. Uses `stlr` for store-with-notify, which sends the event needed to wake the PE.

These are usually paired like:

```
lock.acquire();
defer lock.release();
```

TicketLocks are _not_ reentrant. Deadlock will result if code tries to acquire a lock that it already holds.

