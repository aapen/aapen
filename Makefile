# $Id: Makefile,v 1.9 2007-10-22 18:53:12 rich Exp $

#BUILD_ID_NONE := -Wl,--build-id=none 
BUILD_ID_NONE := 

SHELL	:= /bin/bash

all:	jonesforth

jonesforth: jonesforth.S
	gcc -nostdlib -static $(BUILD_ID_NONE) -o $@ $<

run:
	cat jonesforth.f $(PROG) - | ./jonesforth

clean:
	rm -f jonesforth *~ core

.SUFFIXES: .f
.PHONY: run
