# $Id: Makefile,v 1.9 2007-10-22 18:53:12 rich Exp $

#BUILD_ID_NONE := -Wl,--build-id=none 
#BUILD_ID_NONE := 

#SHELL	:= /bin/bash

COPTS = -Wall -O2 -nostdlib -nostartfiles -ffreestanding 

all: kernel.img

jonesforth.o: jonesforth.S
	gcc $(COPTS) jonesforth.S -o jonesforth.o
#	as jonesforth.S -o jonesforth.o

raspberry.o: raspberry.c
	gcc $(COPTS) -c raspberry.c -o raspberry.o

kernel.img: loadmap jonesforth.o raspberry.o 
	ld jonesforth.o raspberry.o -T loadmap -o pijFORTHos.elf
	objdump -D pijFORTHos.elf > pijFORTHos.list
	objcopy pijFORTHos.elf -O ihex pijFORTHos.hex
	objcopy pijFORTHos.elf -O binary kernel.img

jonesforth: jonesforth.S
	gcc -nostdlib -static -o $@ $<

run:
	cat jonesforth.f $(PROG) - | ./jonesforth

clean:
	rm -f *.o
	rm -f *.bin
	rm -f *.hex
	rm -f *.elf
	rm -f *.list
	rm -f *.img
	rm -f jonesforth *~ core

.SUFFIXES: .f
.PHONY: run
