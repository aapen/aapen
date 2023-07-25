NOTE: this fork is currently broken. I'm attempting to port this from RPi 1 to RPi 4... it's a totally different architecture so the boot code is different, the interrupt controller is different, timers are different, etc.

Currently working:

- Build instructions
- Running under emulation
- Debugging under emulation
- Downloading firmware

Currently not working:

- Running on hardware
- Forth

# Raspberry Pi JonesFORTH O/S

A bare-metal operating system for Raspberry Pi,
based on [_Jonesforth-ARM_](https://github.com/M2IHP13-admin/JonesForth-arm).

_Jonesforth-ARM_ is an ARM port, by M2IHP'13 class members listed in `AUTHORS`, of _x86 JonesForth_.

_x86 JonesForth_ is a Linux-hosted FORTH presented in a Literate Programming style
by Richard W.M. Jones <rich@annexia.org> originally at <http://annexia.org/forth>.
Comments embedded in the original provide an excellent FORTH implementation tutorial.
See the `/annexia/` directory for a copy of this original source.

The algorithm for our unsigned DIVMOD instruction is extracted from 'ARM
Software Development Toolkit User Guide v2.50' published by ARM in 1997-1998

Firmware files to make bootable images are maintained at <https://github.com/raspberrypi/firmware>.
A script in this repository will download these for you.

## What is this ?

_pijFORTHos_ is a bare-metal FORTH interpreter for the [Raspberry Pi](https://en.wikipedia.org/wiki/Raspberry_Pi) (original, Model B).
It follows the general strategy given by David Welch's
[excellent examples](https://github.com/dwelch67/raspberrypi).
A simple [bootloader](/doc/bootload.md#bootloader) is built in,
supporting XMODEM uploads of new bare-metal kernel images.

The interpreter uses the RPi serial console (115200 baud, 8 data bits, no parity, 1 stop bit).
If you have _pijFORTHos_ on an SD card in the RPi,
you can connect it to another machine (even another RPi)
using a [USB-to-Serial cable](http://www.adafruit.com/products/954).
When the RPi is powered on (I provide power through the cable),
a terminal program on the host machine allows access to the FORTH console.

## Board support

Currently supports Raspberry Pi 3b only.

## Build and run instructions

### One-time host setup for cross-compilation

Install a recent Zig build (as of June 2023, we are using nightly builds in the 0.11 series) from https://ziglang.org/download/.

### One-time project setup for firmware

Get the firmware binaries from https://github.com/raspberrypi/firmware

    $ make download_firmware

### One-time install of terminal endpoint

Install https://github.com/tio/tio

### Building Forth

If you're cross-compiling, type:

    $ make clean all

Next, copy the firmware and kernel to a blank FAT32-formatted SD card, for example:

    $ cp firmware/* /media/<SD-card>/
    $ cp kernel8.img /media/<SD-card>/
    $ cp sdfiles/config.txt /media/<SD-card>/

Put the prepared SD card into the RPi, connect the USB-to-Serial cable
(see [RPi Serial Connection](http://elinux.org/RPi_Serial_Connection) for more details),
and power-up to the console.

To get to the console, you'll need to connect. Here are two ways to try:

    $ tio /dev/ttyUSB0

Where `<device>` is something like `/dev/ttyUSB0` or similar
(wherever you plugged in your USB-to-Serial cable).

Alternatively, if `minicom` is not working for you, try using `screen`:

    $ screen <device> 115200

Where `<device>` is, again, something like `/dev/ttyUSB0`.

The console will be waiting for an input, press `<ENTER>`. You should then see:

    pijFORTHos <version> sp=0x00008000

## Debugging on hardware

ARM systems have great support for in-circuit debugging. We can use
GPIO pins to connect to the UART console as well as the JTAG debugging
port. The downside is that this requires two different USB connectors
to the host machine.

If you don't have a spare monitor for the RPi, you can also use an
HDMI capture card to display the video in a window on your host
machine.

```
       ┌────────────┐              ┌────────────┐
       │            │              │            │
       │      Host  │              │ RPi        │
       │            │              │            │
       │       USB 1│◄────────────►│ UART pins  │
       │            │              │            │
       │       USB 2│◄────────────►│ JTAG pins  │
       │            │              │            │
       │            │  ┌────────┐  │            │
       │            │  │HDMI    │  │            │
       │       USB 3│◄─┤Capture │◄─┤ HDMI       │
       │            │  │        │  │            │
       │            │  └────────┘  │            │
       │            │              │            │
       └────────────┘              └────────────┘
```

### UART via USB

UART is serial. USB is serial. All good, right? Well, no. The protocol
is wrong and the voltages are wrong. RPi GPIO uses 3.3v signals. That
will look like a floating pin to USB. Worse, USB will feed +5v to GPIO
which could damage your device.

Generic USB-to-TTL cables seem to work OK. Here is how to make the
connections:

```
USB-to-TTL    RPi GPIO       GPIO pin
label         header pin     (aka Broadcom pin)
----------    ----------     ------------------
3v3           Not connected
TXD           10             GPIO 15 / RXD1
RXD           8              GPIO 14 / TXD1
GND           GND            6
+5V           Not connected
```

We need a common ground but do not want to supply power via this
cable.

### JTAG via USB

Some tutorials recommend the FTDI C232HM DDHSL-0. I was unable to get
this to work.

I have used the [Olimex ARM-USB-TINY-H
rev. C](https://www.olimex.com/Products/ARM/JTAG/ARM-USB-TINY-H/) successfully.

See the ARM-USB-TINY-H's [JTAG
pinout](https://www.olimex.com/Products/ARM/JTAG/_resources/openocd-jtag-layout.png)
for reference.

```
Function   Olimex pin    RPi GPIO       GPIO pin
                         header pin     (aka Broadcom pin)
--------   ----------    ----------     ------------------
Vref       1                            1
GND        4                            9
TRST       3  (blu)      22             15
TDI        5  (grn)      26             37
TMS        7  (yel)      27             13
TCK        9  (ora)      25             22
RTCK       11 (red)      23             16
TDO        13 (brn)      24             18
```

Note that we again create a common ground. In this case we also need
to connect `Vref`.

It's probably a bad idea to run the JTAG and UART USB cables to
different host computers.

### `config.txt` changes for JTAG

To enable JTAG debugging, add the following line to the `config.txt`
on the SD card you will boot the RPi from:

```
enable_jtag_gpio=1
```

Note that this will make the RPi wait for a JTAG connection at boot
time. It will not boot normally without the debugger.

### Host-end software

Another rats' nest of connections, I'm afraid:

- GDB for control of debugging. It connects to OpenOCD
- OpenOCD using the USB-to-JTAG connection to talk to the chip.
- tio as a modem emulator, using the serial device from the to the USB-to-TTL connection. (On Linux this is /dev/ttyUSB0).
- If capturing video, a display program on the host. On Linux, guvcview or OBS both work

```
 ┌────────────────────────────────────┐              ┌────────────┐
 │                                    │              │            │
 │                               Host │              │ RPi        │
 │                                    │              │            │
 │                   tio ◄─────► USB 1│◄────────────►│ UART pins  │
 │                                    │              │            │
 │   GDB ◄─────► OpenOCD ◄─────► USB 2│◄────────────►│ JTAG pins  │
 │                                    │              │            │
 │                                    │  ┌────────┐  │            │
 │                                    │  │HDMI    │  │            │
 │              guvcview ◄─────► USB 3│◄─┤Capture │◄─┤ HDMI       │
 │                                    │  │        │  │            │
 │                                    │  └────────┘  │            │
 │                                    │              │            │
 └────────────────────────────────────┘              └────────────┘
```

To get this running requires three terminal windows (or tmux panes) on the host:

1. Start tio: `tio /dev/ttyUSB0`
2. Start OpenOCD: `./tools/openocd.sh`
3. Start gdb: `make openocd_gdb`

(Note to self: I should add targets to the Makefile for steps 1 and 2)

If everything has worked, gdb will be able to inspect registers, step
through code, and even intercept exceptions.

## Running under emulation

You can install the QEMU ARM support package, then run:

    make emulate
    
This will start `qemu-system-aarch64` emulating a Raspberry Pi model 3b
with its serial I/O connected to your terminal's stdin/stdout.

You can use the Crosstool-built version of GDB to debug the
QEMU-hosted binary. In one terminal window, run:

    $ make debug_emulate

This will tell QEMU to allow GDB remote debugging, and to wait until
the debugger is attached before running the software. To attach GDB,
in another terminal, run:

    $ make gdb
    (gdb) target remote localhost:1234
    (gdb) layout split
    (gdb) break _start
    (gdb) continue

Use `stepi` (or `si` for short) to step by assembly instruction or
`step` to step by source line.

## Where to go from HERE ?

With FORTH REPL running, try typing:

    HEX 8000 DECIMAL 128 DUMP

You should see something like:

    00008000  08 10 4f e2 01 d0 a0 e1  80 e0 9f e5 02 09 a0 e3  |..O.............|
    00008010  01 00 50 e1 44 06 00 0a  00 e0 a0 e1 7f 2c a0 e3  |..P.D........,..|
    00008020  f8 07 b1 e8 f8 07 a0 e8  20 20 52 e2 fb ff ff ca  |........  R.....|
    00008030  1e ff 2f e1 fe ff ff ea  1e ff 2f e1 00 10 80 e5  |../......./.....|
    00008040  1e ff 2f e1 00 00 90 e5  1e ff 2f e1 b0 10 c0 e1  |../......./.....|
    00008050  1e ff 2f e1 b0 00 d0 e1  1e ff 2f e1 00 10 c0 e5  |../......./.....|
    00008060  1e ff 2f e1 00 00 d0 e5  1e ff 2f e1 0e 00 a0 e1  |../......./.....|
    00008070  1e ff 2f e1 10 ff 2f e1  ff 5f 2d e9 f8 07 b1 e8  |../.../.._-.....|

For something a little more interesting, try the [GPIO Morse Code](/doc/blinker.md) tutorial.

The [FORTH reference](/doc/forth.md) page describes the FORTH words available in _pijFORTHos_.

The [Bootloader](/doc/bootload.md) page describes the memory layout and boot process.

There is a persistent thread on the Rasberry Pi forums with a useful collection of
[bare-metal resources](http://www.raspberrypi.org/forums/viewtopic.php?f=72&t=72260),
including ARM CPU programming references and peripheral register descriptions.
