#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

# These need to be in your PATH before you call make
CROSS   = aarch64-unknown-linux-gnu-

AS      = $(CROSS)as
ASFLAGS =

CC      = $(CROSS)gcc
CFLAGS  = -g -Wall -O2 -nostdlib -nostdinc -nostartfiles -ffreestanding

LD      = $(CROSS)ld

OBJDUMP = $(CROSS)objdump
OBJCOPY = $(CROSS)objcopy

QEMU_EXEC       = qemu-system-aarch64
QEMU_BOARD_ARGS = -M raspi3b
QEMU_DEBUG_ARGS = -s -S
QEMU_TEST_ARGS  = -serial stdio -display none

CFILES = $(wildcard *.c)
SFILES = $(wildcard *.s)
OFILES = $(CFILES:.c=.o) $(SFILES:.s=.o)

all: kernel8.img

%.o: %.s
	$(AS) $(ASFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

kernel8.elf: $(OFILES)
	$(LD) $(LDFLAGS) $(OFILES) -T linker.ld -o kernel8.elf

kernel8.img: kernel8.elf
	$(OBJCOPY) kernel8.elf -O binary kernel8.img

emulate: kernel8.img
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_TEST_ARGS) -kernel kernel8.img

debug_emulate: kernel8.img
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel kernel8.img

.c.o:
	$(CC) $(CFLAGS) -c $<

.s.o:
	$(AS) $(ASFLAGS) -c $<

clean:
	rm -f *.o
	rm -f *.bin
	rm -f *.hex
	rm -f *.elf
	rm -f *.list
	rm -f *.img
	rm -f *~ core
