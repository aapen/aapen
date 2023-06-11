#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

QEMU_EXEC       = qemu-system-aarch64
QEMU_BOARD_ARGS = -M raspi3b
QEMU_DEBUG_ARGS = -s -S
QEMU_TEST_ARGS  = -serial stdio -display none -semihosting

GDB_EXEC        = aarch64-unknown-linux-gnu-gdb
GDB_ARGS        = --tui --ex "target remote localhost:1234"

KERNEL_ELF      = zig-out/kernel8.elf
KERNEL          = zig-out/kernel8.img

emulate:
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

debug_emulate:
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel $(KERNEL)

gdb:
	$(GDB_EXEC) $(GDB_ARGS) $(KERNEL_ELF)
