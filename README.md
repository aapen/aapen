# Raspberry Pi JonesFORTH O/S

A bare-metal operating system for Raspberry Pi,
based on _Jonesforth-ARM_ at <https://github.com/M2IHP13-admin/JonesForth-arm>.

_Jonesforth-ARM_ is an ARM port, by M2IHP'13 class members listed in `AUTHORS`, of _x86 JonesForth_.

_x86 JonesForth_ is a Linux-hosted FORTH presented in a Literate Programming style
by Richard W.M. Jones <rich@annexia.org> originally at <http://annexia.org/forth>.
Comments embedded in the original provide an excellent FORTH implementation tutorial.
See the `/annexia/` directory for a copy of this original source.

Firmware files to make bootable images are maintained at <https://github.com/raspberrypi/firmware>.
See the `/firmware/` directory for local copies used in the build process.

## What is this ?

Jonesforth-ARM is a Forth interpreter developed for ARM.

The algorithm for our unsigned DIVMOD instruction is extracted from 'ARM
Software Development Toolkit User Guide v2.50' published by ARM in 1997-1998

Compared to the original interpreter:

 * We did not keep the jonesforth.f section allowing to compile assembly from
   the Forth interpreter because it was X86 specific.

 * We pass all the original JonesForth's tests on ARM (except one which
   depends on the above X86 assembly compilation).

 * We added a native signed DIVMOD instruction (S/MOD)

Another project porting Jonesforth on ARM is ongoing at
https://github.com/phf/forth

## Build and run instructions

If you are building on the ARM target, just type,

	$ make

to build the forth interpreter.

After building, we recommend that you run the test-suite by executing,

	$ make test

To launch the forth interpreter, type

	$ cat jonesforth.f - | ./jonesforth

## Contributors:

ABECASSIS Felix, BISPO VIEIRA Ricardo, BLANC Benjamin, BORDESSOULES Arthur,
BOUDJEMAI Yassine, BRICAGE Marie, ETSCHMANN Marc, GAYE Ndeye Aram,
GONCALVES Thomas, GOUGEAUD Sebastien, HAINE Christopher, OLIVEIRA Pablo,
PLAZA ONATE Florian, POPOV Mihail
