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

KERNEL_ELF	= $(BUILD_DIR)/kernel-$(BOARD)
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
ARCH	= $(shell arch)

ifeq ($(OS), Darwin)
TOOLS_PREFIX	= aarch64-elf-
else ifeq ($(ARCH), aarch64)
TOOLS_PREFIX	=
else
TOOLS_PREFIX	= aarch64-unknown-elf-
endif
GDB_EXEC	= $(TOOLS_PREFIX)gdb

GDB_ARGS	= -s lib
GDB_TARGET_HOST	= --ex "target extended-remote :1234"
GDB_TARGET_DEV	= --ex "target extended-remote :3333"

# Recursively find all files that match a pattern
rwildcard	= $(wildcard $1$2) $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2))

SRC_DIR		= src
BUILD_DIR	= build

S_SRCS          := $(call rwildcard,$(SRC_DIR)/,*.S)
OBJS		:= $(patsubst %.S,%.o,$(patsubst src/%,$(BUILD_DIR)/%,$(S_SRCS)))

F_SRCS          := $(call rwildcard,$(SRC_DIR)/,*.f)

CC		= $(TOOLS_PREFIX)gcc
AS		= $(TOOLS_PREFIX)as
LD		= $(TOOLS_PREFIX)ld

DEBUG_FLAGS	= -g
ASFLAGS		= $(DEBUG_FLAGS) -I $(SRC_DIR) -I include -DBOARD=$(BOARD)
LDFLAGS		= $(DEBUG_FLAGS) -T $(SRC_DIR)/kernel.ld

OBJCOPY		= $(TOOLS_PREFIX)objcopy
OBJFLAGS	= -O binary

.PHONY: kernel_test clean kernels emulate

all: download_firmware emulate

init::
	mkdir -p $(sort $(dir $(OBJS)))

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S
	$(CC) -c $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/armforth.o: $(F_SRCS) 

$(KERNEL): init $(KERNEL_ELF)
	$(OBJCOPY) $(OBJFLAGS) $(KERNEL_ELF) $@

$(KERNEL_ELF): init $(OBJS) $(SRC_DIR)/kernel.ld
	$(LD) $(LDFLAGS) $(OBJS) -o $@

kernels: $(KERNEL)


download_firmware: firmware/COPYING.linux

firmware/COPYING.linux:
	./tools/fetch_firmware.sh

emulate: $(KERNEL) firmware/COPYING.linux
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_NOBUG_ARGS) -kernel $(KERNEL)

debug_emulate: $(KERNEL) firmware/COPYING.linux
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
	rm -rf $(BUILD_DIR)
