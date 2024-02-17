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


## Semaphores

### Construction

`semaphore.create(initial_count: SemaphoreCount) !SID`

Claims and initializes a semaphore. Returns the semaphore ID (SID). Can return error if no more semaphores are available.

### Free

`semaphore.free(sid: SID) !void`

Releases a semaphore. If any threads are waiting on it, they will be marked ready. (Note that the thread may be surprised to learn it's been woken on a semaphore that no longer exists.) Can return error if the semaphore ID is illegal or the semaphore is not currently in use. (I.e., use after free.)

### Wait

`semaphore.wait(sid: SID) !void`

Attempts to "take" a resource by decrementing the semaphore's count. If that would go negative, the thread will block until the semaphore is signalled by some other thread. Can return error if the semaphore ID is illegal or the semaphore is not currently in use.

### Signal

`semaphore.signal(sid: SID) !void`

Releases a resource by incrementing the semaphore's count. If there are any threads waiting on the semaphore, this will wake one of them to run. It will be scheduled immediately and a context switch might result. Can return error if the semaphore ID is illegal or the semaphore is not currently in use.

### Signal N

`semaphore.signal(sid: SID, count: SemaphoreCount) !void`

Releases `count` resources by incrementing the semaphore's count. If there are threads waiting on the semaphore, `count` of them will be woken. A reschedule will be done after all the threads are woken and a context switch might result. Can return error if the semaphore ID is illegal or the semaphore is not currently in use.
