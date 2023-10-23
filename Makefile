#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

ZIG             = zig
ZIG_BUILD_ARGS  = -Doptimize=Debug -freference-trace

# Could we possibly have a zig build command that would simply output
# all of the different board flavors? Otherwise we can make this
# a simple make assignment.
BOARD_FLAVORS   = $(shell echo pi3 pi4 pi400 pi5)

ELF_FILES = $(addprefix zig-out/kernel-,$(addsuffix .elf,$(BOARD_FLAVORS)))
KERNEL_FILES = $(addprefix zig-out/kernel-,$(addsuffix .img,$(BOARD_FLAVORS)))

QEMU_EXEC       = qemu-system-aarch64 -semihosting
QEMU_BOARD_ARGS = -M raspi3b -dtb firmware/bcm2710-rpi-3-b.dtb
#QEMU_BOARD_ARGS = -M raspi3b -dtb firmware/bcm2711-rpi-400.dtb
QEMU_DEBUG_ARGS = -s -S -serial pty
QEMU_NOBUG_ARGS = -serial stdio

OS              = $(shell uname)
ifeq ($(OS), Darwin)
GDB_EXEC        = aarch64-elf-gdb
else
GDB_EXEC        = aarch64-unknown-linux-gnu-gdb
endif

GDB_ARGS        = -s lib
GDB_TARGET_HOST = --ex "target remote :1234"
GDB_TARGET_DEV  = --ex "target extended-remote :3333"

# KERNEL_ELF      = zig-out/kernel8.elf
# KERNEL          = zig-out/kernel8.img

rwildcard       =$(wildcard $1$2) $(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2))

# How to recursively find all files that match a pattern
SRCS           := $(call rwildcard,src/,*.zig) $(call rwildcard,src/,*.f) $(call rwildcard,src/,*.S)

TEST_SRC        = src/tests.zig

.PHONY: test clean


all: init emulate

init: download_firmware dirs

dirs:
	mkdir -p zig-out

kernels: $(KERNEL_FILES)

zig-out/kernel-%.img: $(SOURCES)
	$(ZIG) build -Dboard=$(*F) -Dimage=kernel-$(*F) $(ZIG_BUILD_ARGS)

download_firmware: firmware/COPYING.linux

firmware/COPYING.linux:
	./tools/fetch_firmware.sh

test:
	$(ZIG) test $(TEST_SRC)

emulate: $(KERNEL) firmware/COPYING.linux
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_NOBUG_ARGS) -kernel $(KERNEL)

debug_emulate: $(KERNEL) firmware/COPYING.linux
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_HOST) $(KERNEL_ELF)

openocd_gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_DEV) $(KERNEL_ELF)

sdcard: $(KERNEL) firmware/COPYING.linux
ifndef SDCARD_PATH
	$(error "SDCARD_PATH must be defined as an environment variable.")
else
	mkdir -p $(SDCARD_PATH)
	cp -r firmware/* $(SDCARD_PATH)
	cp $(KERNEL) $(SDCARD_PATH)
	cp sdfiles/config.txt $(SDCARD_PATH)
endif

clean:
	rm -rf zig-cache
	rm -rf $(KERNEL_ELF) $(KERNEL)
