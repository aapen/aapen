BOARD_FLAVORS	= $(shell echo pi3 pi4)

# Change this to set the board flavor used in the emulator.
# Must be one in the list above.
BOARD		= pi3

EMU_pi3		= raspi3b
FIRMWARE_pi3	= bcm2710-rpi-3-b.dtb

EMU_pi4		= raspi4b
FIRMWARE_pi4	= bcm2711-rpi-4-b.dtb

EMUBOARD	= ${EMU_${BOARD}}
FIRMWARE	= ${FIRMWARE_${BOARD}}

KERNEL_ELF	= build/kernel-$(BOARD)
KERNEL		= $(KERNEL_ELF).img

CORE_COUNT	= 4
QEMU_EXEC	= qemu-system-aarch64 -semihosting -smp $(CORE_COUNT)

ifdef SDIMAGE
  SD_ARGS	= -drive if=sd,format=raw,file=$(SDIMAGE)
else
  SD_ARGS	=
endif

QEMU_BOARD_ARGS	= -M $(EMUBOARD) -dtb firmware/$(FIRMWARE) $(SD_ARGS)
QEMU_DEBUG_ARGS	= -s -S -serial pty -monitor telnet:localhost:1235,server,nowait -device usb-kbd -device usb-mouse -trace 'events=etc/trace_events.txt'

# Use this to get USB tracing from the emulator.
QEMU_NOBUG_ARGS	= -serial stdio -device usb-kbd -device usb-mouse -trace 'events=etc/trace_events.txt'

OS		= $(shell uname)
ifeq ($(OS), Darwin)
TOOLS_PREFIX	= aarch64-elf-
else
TOOLS_PREFIX	= aarch64-unknown-linux-gnu-
endif
GDB_EXEC	= $(TOOLS_PREFIX)gdb

GDB_ARGS	= -s lib
GDB_TARGET_HOST	= --ex "target extended-remote :1234"
GDB_TARGET_DEV	= --ex "target extended-remote :3333"

# Recursively find all files that match a pattern
rwildcard	= $(wildcard $1$2) $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2))

ARCH		= src/arch/aarch64
S_SRCS          := $(call rwildcard,src/,*.S)
OBJS		:= $(patsubst %.S,%.o,$(patsubst src/%,build/%,$(S_SRCS)))

CC		= $(TOOLS_PREFIX)gcc
AS		= $(TOOLS_PREFIX)as
ASFLAGS		= -I src -I include -DBOARD=$(BOARD)

LD		= $(TOOLS_PREFIX)ld
LDFLAGS		= -T $(ARCH)/kernel.ld

OBJCOPY		= $(TOOLS_PREFIX)objcopy
OBJFLAGS	= -O binary

.PHONY: kernel_test clean kernels emulate

all: download_firmware emulate

init::
	# A side effect of sort is the it deletes duplicates,
	# which is why we use it here.
	mkdir -p $(sort $(dir $(OBJS)))

build/%.o: src/%.S
	$(CC) -c $(ASFLAGS) -o $@ $<

$(KERNEL): init $(KERNEL_ELF)
	$(OBJCOPY) $(OBJFLAGS) $(KERNEL_ELF) $@

$(KERNEL_ELF): init $(OBJS) $(ARCH)/kernel.ld
	$(LD) $(LDFLAGS) $(OBJS) -o $@

$(ARCH)/armforth.o: $(OBJS)

download_firmware: firmware/COPYING.linux

firmware/COPYING.linux:
	./tools/fetch_firmware.sh

emulate: $(KERNEL) firmware/COPYING.linux
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_NOBUG_ARGS) -kernel $(KERNEL)

debug_emulate: $(TEST_KERNEL) firmware/COPYING.linux
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_HOST) $(KERNEL_ELF)

openocd_gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_DEV) $(KERNEL_ELF)

openocd_gdb2: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) --ex "target extended-remote :3334" $(KERNEL_ELF)

sdcard: $(KERNEL) firmware/COPYING.linux
ifndef SDCARD_PATH
	$(error "SDCARD_PATH must be defined as an environment variable.")
else
	mkdir -p $(SDCARD_PATH)
	cp -r firmware/* $(SDCARD_PATH)
	cp $(KERNEL) $(SDCARD_PATH)
	cp sdfiles/config.txt $(SDCARD_PATH)
endif

nuke:	clean all

sdfiles/infloop.bin:
	echo "0000: 0000 0014" | xxd -r - sdfiles/infloop.bin

clean:
	rm -rf build
