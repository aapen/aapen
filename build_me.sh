#!/bin/bash
zig build-exe io.zig boot.s qemu.s -T kernel.ld -target aarch64-freestanding-none
mv io kernel8.elf
zig objcopy -O binary kernel8.elf kernel8.img

# Run qemu thusly:
#  qemu-system-aarch64 -M raspi3b -serial stdio -display none -semihosting -kernel kernel8.img
#
# or if you want to debug with gdb:
#  qemu-system-aarch64 -M raspi3b -serial stdio -display none -semihosting -kernel kernel8.img -s -S
