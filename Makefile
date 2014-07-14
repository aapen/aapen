#
# Makefile for pijFORTHos -- Raspberry Pi JonesFORTH Operating System
#

AS=	as
CC=	gcc -g -Wall -O2 -nostdlib -nostartfiles -ffreestanding
LD=	ld

KOBJS=	start.o jonesforth.o raspberry.o timer.o serial.o xmodem.o

all: kernel.img

start.o: start.s
	$(AS) start.s -o start.o

jonesforth.o: jonesforth.s
	$(AS) jonesforth.s -o jonesforth.o

#raspberry.o: raspberry.c
#	$(CC) -c raspberry.c -o raspberry.o

kernel.img: loadmap $(KOBJS)
	$(LD) $(KOBJS) -T loadmap -o pijFORTHos.elf
	objdump -D pijFORTHos.elf > pijFORTHos.list
	objcopy pijFORTHos.elf -O ihex pijFORTHos.hex
	objcopy --only-keep-debug pijFORTHos.elf kernel.sym
	objcopy pijFORTHos.elf -O binary kernel.img

.c.o:
	$(CC) -c $<

clean:
	rm -f *.o
	rm -f *.bin
	rm -f *.hex
	rm -f *.elf
	rm -f *.list
	rm -f *.img
	rm -f *~ core
