#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

COPTS = -g -Wall -O2 -nostdlib -nostartfiles -ffreestanding

all: kernel.img

start.o: start.s
	as start.s -o start.o

jonesforth.o: jonesforth.s
	as jonesforth.s -o jonesforth.o

raspberry.o: raspberry.c
	gcc $(COPTS) -c raspberry.c -o raspberry.o

kernel.img: loadmap start.o jonesforth.o raspberry.o 
	ld start.o jonesforth.o raspberry.o -T loadmap -o pijFORTHos.elf
	objdump -D pijFORTHos.elf > pijFORTHos.list
	objcopy pijFORTHos.elf -O ihex pijFORTHos.hex
	objcopy --only-keep-debug pijFORTHos.elf kernel.sym
	objcopy pijFORTHos.elf -O binary kernel.img

clean:
	rm -f *.o
	rm -f *.bin
	rm -f *.hex
	rm -f *.elf
	rm -f *.list
	rm -f *.img
	rm -f *~ core
