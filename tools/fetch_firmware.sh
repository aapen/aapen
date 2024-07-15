#! /bin/bash

BASE=https://github.com/raspberrypi/firmware/raw/master/boot

# File list as of 9 June 2023
FILES=("COPYING.linux"
       "LICENCE.broadcom"
       "bcm2708-rpi-b-plus.dtb"
       "bcm2708-rpi-b-rev1.dtb"
       "bcm2708-rpi-b.dtb"
       "bcm2708-rpi-cm.dtb"
       "bcm2708-rpi-zero-w.dtb"
       "bcm2708-rpi-zero.dtb"
       "bcm2709-rpi-2-b.dtb"
       "bcm2709-rpi-cm2.dtb"
       "bcm2710-rpi-2-b.dtb"
       "bcm2710-rpi-3-b-plus.dtb"
       "bcm2710-rpi-3-b.dtb"
       "bcm2710-rpi-cm3.dtb"
       "bcm2710-rpi-zero-2-w.dtb"
       "bcm2710-rpi-zero-2.dtb"
       "bcm2711-rpi-4-b.dtb"
       "bcm2711-rpi-400.dtb"
       "bcm2711-rpi-cm4-io.dtb"
       "bcm2711-rpi-cm4.dtb"
       "bcm2711-rpi-cm4s.dtb"
       "bcm2712-rpi-5-b.dtb"
       "bcm2712-rpi-cm5-cm4io.dtb"
       "bcm2712-rpi-cm5-cm5io.dtb"
       "bcm2712d0-rpi-5-b.dtb"
       "bootcode.bin"
       "fixup.dat"
       "fixup4.dat"
       "fixup4cd.dat"
       "fixup4db.dat"
       "fixup4x.dat"
       "fixup_cd.dat"
       "fixup_db.dat"
       "fixup_x.dat"
       "kernel.img"
       "kernel7.img"
       "kernel7l.img"
       "kernel8.img"
       "kernel_2712.img"
       "start.elf"
       "start4.elf"
       "start4cd.elf"
       "start4db.elf"
       "start4x.elf"
       "start_cd.elf"
       "start_db.elf"
       "start_x.elf")

for f in ${FILES[@]}
do
    wget -O firmware/$f $BASE/$f
done
