#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

ZIG             = zig
ZIG_BUILD_ARGS  = -Doptimize=Debug

QEMU_EXEC       = qemu-system-aarch64
QEMU_BOARD_ARGS = -M raspi3b -dtb firmware/bcm2710-rpi-3-b.dtb
QEMU_DEBUG_ARGS = -s -S
QEMU_TEST_ARGS  = -serial stdio -display none -semihosting

GDB_EXEC        = aarch64-unknown-linux-gnu-gdb
GDB_ARGS        = -s lib
GDB_TARGET_HOST = --ex "target remote :1234"
GDB_TARGET_DEV  = --ex "target remote :3333"

KERNEL_ELF      = zig-out/kernel8.elf
KERNEL          = zig-out/kernel8.img

all: init emulate

init: download_firmware dirs

dirs:
	mkdir -p zig-out

download_firmware: firmware/COPYING.linux

firmware/COPYING.linux:
	./scripts/fetch_firmware.sh

$(KERNEL):
	$(ZIG) build $(ZIG_BUILD_ARGS)

emulate: $(KERNEL)
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

debug_emulate: $(KERNEL)
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_HOST) $(KERNEL_ELF)

openocd_gdb: $(KERNEL)
	$(GDB_EXEC) $(GDB_ARGS) $(GDB_TARGET_DEV) $(KERNEL_ELF)

clean:
	rm -rf zig-cache
	rm -rf $(KERNEL_ELF) $(KERNEL)
