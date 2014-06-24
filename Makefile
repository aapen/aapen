# $Id: Makefile,v 1.9 2007-10-22 18:53:12 rich Exp $

#BUILD_ID_NONE := -Wl,--build-id=none 
#BUILD_ID_NONE := 

#SHELL	:= /bin/bash

COPTS = -Wall -O2 -nostdlib -nostartfiles -ffreestanding 

all: kernel.img

jonesforth.o: jonesforth.S
	as -o jonesforth.o jonesforth.S

raspberry.o: raspberry.c
	gcc $(COPTS) -o raspberry.o -c raspberry.c

kernel.img: loadmap jonesforth.o raspberry.o 
	ld -T loadmap -o pijFORTHos.elf jonesforth.o raspberry.o
	objdump -D pijFORTHos.elf > pijFORTHos.list
	objcopy -O ihex pijFORTHos.hex pijFORTHos.elf
	objcopy -O binary kernel.img pijFORTHos.elf

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
