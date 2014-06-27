# $Id: Makefile,v 1.9 2007-10-22 18:53:12 rich Exp $

BUILD_ID := -Wl,--build-id=none 
#BUILD_ID := 

COPTS = -Wall -O2 -nostdlib -nostartfiles -ffreestanding 

all: kernel.img

start.o: start.s
	as start.s -o start.o

jonesforth.o: jonesforth.S
	gcc $(COPTS) $(BUILD_ID) jonesforth.S -o jonesforth.o

raspberry.o: raspberry.c
	gcc $(COPTS) -c raspberry.c -o raspberry.o

kernel.img: loadmap start.o jonesforth.o raspberry.o 
	ld start.o jonesforth.o raspberry.o -T loadmap -o pijFORTHos.elf
	objdump -D pijFORTHos.elf > pijFORTHos.list
	objcopy pijFORTHos.elf -O ihex pijFORTHos.hex
	objcopy pijFORTHos.elf -O binary kernel.img

clean:
	rm -f *.o
	rm -f *.bin
	rm -f *.hex
	rm -f *.elf
	rm -f *.list
	rm -f *.img
	rm -f *~ core
