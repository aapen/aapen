#! /bin/bash

# For RPi3
mkdir -p firmware/rpi3
wget -O firmware/rpi3/start.elf https://github.com/raspberrypi/firmware/raw/master/boot/start.elf
wget -O firmware/rpi3/fixup.dat https://github.com/raspberrypi/firmware/raw/master/boot/fixup.dat
wget -O firmware/rpi3/bootcode.bin https://github.com/raspberrypi/firmware/blob/master/boot/bootcode.bin
wget -O firmware/rpi3/bcm2710-rpi-3-b.dtb https://raw.githubusercontent.com/raspberrypi/firmware/master/boot/bcm2710-rpi-3-b.dtb

# For RPi4
mkdir -p firmware/rpi4
wget -O firmware/rpi4/start4.elf https://github.com/raspberrypi/firmware/raw/master/boot/start4.elf
wget -O firmware/rpi4/fixup4.dat https://github.com/raspberrypi/firmware/raw/master/boot/fixup4.dat
wget -O firmware/rpi4/bootcode.bin https://github.com/raspberrypi/firmware/blob/master/boot/bootcode.bin
wget -O firmware/rpi4/bcm2711-rpi-4-b.dtb https://github.com/raspberrypi/firmware/raw/master/boot/bcm2711-rpi-4-b.dtb
