#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

QEMU_EXEC       = qemu-system-aarch64
QEMU_BOARD_ARGS = -M raspi3b
QEMU_DEBUG_ARGS = -s -S
QEMU_TEST_ARGS  = -serial stdio -display none -semihosting

emulate:
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_TEST_ARGS) -kernel kernel8.img

debug_emulate:
	$(QEMU_EXEC) $(QEMU_BOARD_ARGS) $(QEMU_DEBUG_ARGS) $(QEMU_TEST_ARGS) -kernel kernel8.img

