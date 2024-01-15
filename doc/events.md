# Events

Interrupts, I/O completion, and any other asynchronous notifications
to application code are provided via an event queuing mechanism. The
kernel has a ring buffer that can hold 1k events. If an application
falls too far behind, old events will be overwritten by newer
ones. This avoids dynamic memory allocation in a part of the system
that needs low latency.

## Kernel API

Inside the kernel, there are two functions that enqueue and dequeue an
event.

`enqueue(ev: Event) void` - copies the contents of the event into the
queue. The caller is free to reuse the memory however it wants. This
is probably going to be called mainly from interrupt handlers. When
the queue depth goes from zero to non-zero, it will notify one parked
CPU.

`dequeue() Event` - returns a copy of the event. The caller is free to
use the memory however it wants. If there is no event available,
`dequeue` will park the CPU until an event arrives. Since there is no
ability to filter the events before receiving them, the caller should
expect to handle every event type.

One function allows a caller to check whether there are events
currently in queue.

`peek() ?Event` - if there are events in the queue, return a copy of
the next one. The event remains in the queue. This will not park the
CPU, though it might wait briefly on a spinlock or critical section.

## Forty API

`next-event` - if there is an event in the queue, push it's value (as
a 64 bit doubleword) onto the stack.

dispatching TBD but we will need to at least dispatch I/O completion
on USB transfers to call back to their respective drivers.

## Event structure

Every event shares a common header and a fixed size. The first two
bytes specify the event type and subtype, which are system
defined. The remainder of the first word and the entire second word
are interpreted depending on the event type.

```
                 1                    3
0       7        5                    1
+--------+--------+--------------------+
| type   | subtype| value              |
+--------+--------+--------------------+
| extra                                |
+--------------------------------------+
```

The entire event fits into a 64 bit doubleword. If the event needs to
convey more information to application code than can fit into 64 bits,
the `extra` field can be used as a pointer to lower memory. In extreme
cases, the `value` can also be used as the upper 16 bits of an
address, thereby allowing a pointer to anywhere in the 48 bit address
space.

## Event Types

The following event types are defined:

```
+-------+------------------------------+
| type  | meaning                      |
+-------+------------------------------+
|  0x01 | GPIO                         |
|  0x02 | Key                          |
|  0x03 | Mouse                        |
|  0x04 | I/O completion               |
|  0x05 | I2C                          |
|  0x06 | SPI                          |
|  0x07 | Timer                        |
+-------+------------------------------+
```

### GPIO

GPIO events only occur if the application code configures the GPIO
pins to deliver certain interrupts. For example, a "rising edge
detected" event can only occur if the pin is configured to trigger on
edge detection.

Type: 0x01

Subtypes:
```
+---------+-----------------------+
| subtype | meaning               |
+---------+-----------------------+
|    0b00 | rising edge detected  |
|    0b01 | falling edge detected |
|    0b10 | level high detected   |
|    0b10 | level low detected    |
+---------+-----------------------+
```

Value: Broadcom pin #

Extra: not used

### Key

Key events can come from any attached USB keyboard.

Type: 0x02

Subtypes:

```
+---------+---------------+
| subtype | meaning       |
+---------+---------------+
|    0x00 | key pressed   |
|    0x01 | key released  |
+---------+---------------+
```

A key event's value encodes the keycode and modifier state:

```
                 1 
0       7        5 
+--------+--------+
|keycode | mods   |
+--------+--------+
```

Where mods is a bitfield:

```
+-----+--------------------+
| bit | modifier pressed   |
+-----+--------------------+
|   0 | shift              |
|   1 | alt                |
|   2 | control            |
|   3 | super              |
+-----+--------------------+
```

Extra is not used at this time but might be used to provide "exploded"
modifiers so we can distinguish left shift from right shift.

### Mouse

Type: 0x03

Subtype: TBD

Value: TBD

Extra: TBD

### I/O completion

Type: 0x04

Subtypes: 

```
+---------+---------------+
| subtype | meaning       |
+---------+---------------+
|    0x00 | succeeded     |
|    0x7f | failed        |
+---------+---------------+
```

If subtype is 0x01, then value contains an error code. 

```
Error code table TBD
```

Extra: caller-private word that was supplied when starting the I/O

### I2C

Type: 0x05

Subtypes: TBD

Value: TBD

Extra: TBD

### SPI

Type: 0x06

Subtypes: TBD

Value: TBD

Extra: TBD

### Timer

Type: 0x07

Subtype: not used

Value: not used

Extra: caller-private word that was supplied when starting the timer
