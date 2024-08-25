/*	A sometimes minimal FORTH compiler and tutorial for Linux / i386 systems. -*- asm -*-
	By Richard W.M. Jones <rich@annexia.org> http://annexia.org/forth
	This is PUBLIC DOMAIN (see public domain release statement below).
	$Id: jonesforth.S,v 1.42 2007/10/07 11:07:15 rich Exp $

	gcc -nostdlib -static -Wl,-Ttext,0 -Wl,--build-id=none -o jonesforth jonesforth.S
*/

#include <asm/macro.h>
#include <asm/aarch64/rpi3_registers.h>

	.set JONES_VERSION,47

        /* RPi3 */
        .set PERIPHERALS, 0x3f000000

/*

        ARM32 port by Peter H. Froelich. Attribution follows:

        JONESFORTH/arm: Porting Richard Jones' FORTH to ARM

        Hacked in 2010, 2016 by Peter H. Froehlich.

        JONESFORTH/arm is in the Public Domain, see README.md for all the details.
*/

	.set ARM_VERSION,1

/*

        Aarch64 port by Michael T. Nygard. Attribution follows:

        JONESFORTH/aarch64: Porting Richard Jones' FORTH to Aarch64
        (a.k.a. ARM64)

        Literate comments restored & partially updated to describe ARM64 conventions. Many
        x86-isms remain in Richard's description of the direct threaded execution model

 */


/*
        Aapen modifications:
        - Remove Linux-isms: no syscalls to SYS_EXIT, SYS_OPENAT,
          SYS_CLOSE, SYS_READ, SYS_WRITE, and very crucially, SYS_BRK
        - Accordingly, the SYSCALL0 .. SYSCALL4 words are removed
        - Instead of asking operating system for memory, the start & end of allowed memory is
          reserved as BSS
        - KEY doesn't get to call SYS_READ... it uses an input routine supplied by the
          kernel as _forth_getch

*/



/*
	INTRODUCTION ----------------------------------------------------------------------

	FORTH is one of those alien languages which most working programmers regard in the same
	way as Haskell, LISP, and so on.  Something so strange that they'd rather any thoughts
	of it just go away so they can get on with writing this paying code.  But that's wrong
	and if you care at all about programming then you should at least understand all these
	languages, even if you will never use them.

	LISP is the ultimate high-level language, and features from LISP are being added every
	decade to the more common languages.  But FORTH is in some ways the ultimate in low level
	programming.  Out of the box it lacks features like dynamic memory management and even
	strings.  In fact, at its primitive level it lacks even basic concepts like IF-statements
	and loops.

	Why then would you want to learn FORTH?  There are several very good reasons.  First
	and foremost, FORTH is minimal.  You really can write a complete FORTH in, say, 2000
	lines of code.  I don't just mean a FORTH program, I mean a complete FORTH operating
	system, environment and language.  You could boot such a FORTH on a bare PC and it would
	come up with a prompt where you could start doing useful work.  The FORTH you have here
	isn't minimal and uses a Linux process as its 'base PC' (both for the purposes of making
	it a good tutorial). It's possible to completely understand the system.  Who can say they
	completely understand how Linux works, or gcc?

	Secondly FORTH has a peculiar bootstrapping property.  By that I mean that after writing
	a little bit of assembly to talk to the hardware and implement a few primitives, all the
	rest of the language and compiler is written in FORTH itself.  Remember I said before
	that FORTH lacked IF-statements and loops?  Well of course it doesn't really because
	such a lanuage would be useless, but my point was rather that IF-statements and loops are
	written in FORTH itself.

	Now of course this is common in other languages as well, and in those languages we call
	them 'libraries'.  For example in C, 'printf' is a library function written in C.  But
	in FORTH this goes way beyond mere libraries.  Can you imagine writing C's 'if' in C?
	And that brings me to my third reason: If you can write 'if' in FORTH, then why restrict
	yourself to the usual if/while/for/switch constructs?  You want a construct that iterates
	over every other element in a list of numbers?  You can add it to the language.  What
	about an operator which pulls in variables directly from a configuration file and makes
	them available as FORTH variables?  Or how about adding Makefile-like dependencies to
	the language?  No problem in FORTH.  How about modifying the FORTH compiler to allow
	complex inlining strategies -- simple.  This concept isn't common in programming languages,
	but it has a name (in fact two names): "macros" (by which I mean LISP-style macros, not
	the lame C preprocessor) and "domain specific languages" (DSLs).

	This tutorial isn't about learning FORTH as the language.  I'll point you to some references
	you should read if you're not familiar with using FORTH.  This tutorial is about how to
	write FORTH.  In fact, until you understand how FORTH is written, you'll have only a very
	superficial understanding of how to use it.

	So if you're not familiar with FORTH or want to refresh your memory here are some online
	references to read:

	http://en.wikipedia.org/wiki/Forth_%28programming_language%29

	http://galileo.phys.virginia.edu/classes/551.jvn.fall01/primer.htm

	http://wiki.laptop.org/go/Forth_Lessons

	http://www.albany.net/~hello/simple.htm

	Here is another "Why FORTH?" essay: http://www.jwdt.com/~paysan/why-forth.html

	Discussion and criticism of this FORTH here: http://lambda-the-ultimate.org/node/2452

	ACKNOWLEDGEMENTS ----------------------------------------------------------------------

	This code draws heavily on the design of LINA FORTH (http://home.hccnet.nl/a.w.m.van.der.horst/lina.html)
	by Albert van der Horst.  Any similarities in the code are probably not accidental.

	Some parts of this FORTH are also based on this IOCCC entry from 1992:
	http://ftp.funet.fi/pub/doc/IOCCC/1992/buzzard.2.design.
	I was very proud when Sean Barrett, the original author of the IOCCC entry, commented in the LtU thread
	http://lambda-the-ultimate.org/node/2452#comment-36818 about this FORTH.

	And finally I'd like to acknowledge the (possibly forgotten?) authors of ARTIC FORTH because their
	original program which I still have on original cassette tape kept nagging away at me all these years.
	http://en.wikipedia.org/wiki/Artic_Software

	PUBLIC DOMAIN ----------------------------------------------------------------------

	I, the copyright holder of this work, hereby release it into the public domain. This applies worldwide.

	In case this is not legally possible, I grant any entity the right to use this work for any purpose,
	without any conditions, unless such conditions are required by law.

	SETTING UP ----------------------------------------------------------------------

	Let's get a few housekeeping things out of the way.  Firstly because I need to draw lots of
	ASCII-art diagrams to explain concepts, the best way to look at this is using a window which
	uses a fixed width font and is at least this wide:

 <------------------------------------------------------------------------------------------------------------------------>

	Secondly make sure TABS are set to 8 characters.  The following should be a vertical
	line.  If not, sort out your tabs.

	|
        |
	|

	Thirdly I assume that your screen is at least 50 characters high.

	ASSEMBLING ----------------------------------------------------------------------

	If you want to actually run this FORTH, rather than just read it, you will need Linux on
	an ARM64.  Linux because instead of programming directly to the hardware on a bare PC
	which I could have done, I went for a simpler tutorial by assuming that the 'hardware' is
	a Linux process with a few basic system calls (read, write and exit and that's about all).
	[NOTE: Richard's original targeted i386 as the more commonly available PC processor.]
	ARM64 is used here for the hobbyist tinkering with Raspberry Pi or similar SBCs.

	Again, to assemble this you will need gcc and gas (the GNU assembler).  The commands to
	assemble and run the code (save this file as 'jonesforth.S') are:

	gcc -nostdlib -static -Wl,-Ttext,0 -Wl,--build-id=none -o jonesforth jonesforth.S
	cat jonesforth.f - | ./jonesforth

	If you want to run your own FORTH programs you can do:

	cat jonesforth.f myprog.f | ./jonesforth

	If you want to load your own FORTH code and then continue reading user commands, you can do:

	cat jonesforth.f myfunctions.f - | ./jonesforth

	ASSEMBLER ----------------------------------------------------------------------

	(You can just skip to the next section -- you don't need to be able to read assembler to
	follow this tutorial).

	However if you do want to read the assembly code here are a few notes about gas (the GNU assembler):

	(1) Registers have two names each: "x0" refers to the 64 bit wide general purpose register
  	    0. "w0" refers to the bottom 32 bit word of that register. Some operations (such as
  	    loading and storing bytes) only allow the word-sized version like "w0".

	(2) Add, mov, etc. take arguments in the form DEST, SRC.  So mov x0, x1 moves x1 -> x0

	(3) Constants are prefixed with '#'

	(4) gas has a funky syntax for local labels, where '1f' (etc.) means label '1:' "forwards"
	    and '1b' (etc.) means label '1:' "backwards".

	(5) gas has a reasonably nice .macro syntax, and I use them a lot to make the code shorter and
	    less repetitive.

	For more help reading the assembler, do "info gas" at the Linux prompt.

	Now the tutorial starts in earnest.

	THE DICTIONARY ----------------------------------------------------------------------

	In FORTH as you will know, functions are called "words", and just as in other languages they
	have a name and a definition.  Here are two FORTH words:

	: double DUP + ;		\ name is "double", definition is "DUP +"
	: quadruple double double ;	\ name is "quadruple", definition is "double double"

	Words, both built-in ones and ones which the programmer defines later, are stored in a dictionary
	which is just a linked list of dictionary entries.

	<--- DICTIONARY ENTRY (HEADER) ----------------------->
	+------------------------+--------+---------- - - - - +----------- - - - -
	| LINK POINTER           | LENGTH/| NAME 	      | DEFINITION
	|			 | FLAGS  |     	      |
	+--- (4 bytes) ----------+- byte -+- n bytes  - - - - +----------- - - - -

	link_pointer[4] flags[1] namelen[1] name[n] definition


	I'll come to the definition of the word later.  For now just look at the header.  The first
	4 bytes are the link pointer.  This points back to the previous word in the dictionary, or, for
	the first word in the dictionary it is just a NULL pointer.  Then comes a length/flags byte.
	The length of the word can be up to 31 characters (5 bits used) and the top three bits are used
	for various flags which I'll come to later.  This is followed by the name itself, and in this
	implementation the name is rounded up to a multiple of 4 bytes by padding it with zero bytes.
	That's just to ensure that the definition starts on a 32 bit boundary.

	A FORTH variable called LATEST contains a pointer to the most recently defined word, in
	other words, the head of this linked list.

	double and quadruple might look like this:

	  pointer to previous word
	   ^
	   |
	+--|------+---+---+---+---+---+---+---+---+------------- - - - -
	| LINK    | 6 | D | O | U | B | L | E | 0 | (definition ...)
	+---------+---+---+---+---+---+---+---+---+------------- - - - -
           ^       len                         padding
	   |
	+--|------+---+---+---+---+---+---+---+---+---+---+---+---+------------- - - - -
	| LINK    | 9 | Q | U | A | D | R | U | P | L | E | 0 | 0 | (definition ...)
	+---------+---+---+---+---+---+---+---+---+---+---+---+---+------------- - - - -
           ^       len                                     padding
           |
           |
	  LATEST

	You should be able to see from this how you might implement functions to find a word in
	the dictionary (just walk along the dictionary entries starting at LATEST and matching
	the names until you either find a match or hit the NULL pointer at the end of the dictionary);
	and add a word to the dictionary (create a new definition, set its LINK to LATEST, and set
	LATEST to point to the new word).  We'll see precisely these functions implemented in
	assembly code later on.

	One interesting consequence of using a linked list is that you can redefine words, and
	a newer definition of a word overrides an older one.  This is an important concept in
	FORTH because it means that any word (even "built-in" or "standard" words) can be
	overridden with a new definition, either to enhance it, to make it faster or even to
	disable it.  However because of the way that FORTH words get compiled, which you'll
	understand below, words defined using the old definition of a word continue to use
	the old definition.  Only words defined after the new definition use the new definition.

	DIRECT THREADED CODE ----------------------------------------------------------------------

	Now we'll get to the really crucial bit in understanding FORTH, so go and get a cup of tea
	or coffee and settle down.  It's fair to say that if you don't understand this section, then you
	won't "get" how FORTH works, and that would be a failure on my part for not explaining it well.
	So if after reading this section a few times you don't understand it, please email me
	(rich@annexia.org).

	Let's talk first about what "threaded code" means.  Imagine a peculiar version of C where
	you are only allowed to call functions without arguments.  (Don't worry for now that such a
	language would be completely useless!)  So in our peculiar C, code would look like this:

	f ()
	{
	  a ();
	  b ();
	  c ();
	}

	and so on.  How would a function, say 'f' above, be compiled by a standard C compiler?
	Probably into assembly code like this.  On the right hand side I've written the actual
	i386 machine code.

	f:
	  CALL a			E8 08 00 00 00
	  CALL b			E8 1C 00 00 00
	  CALL c			E8 2C 00 00 00
	  ; ignore the return from the function for now

	"E8" is the x86 machine code to "CALL" a function.  In the first 20 years of computing
	memory was hideously expensive and we might have worried about the wasted space being used
	by the repeated "E8" bytes.  We can save 20% in code size (and therefore, in expensive memory)
	by compressing this into just:

	08 00 00 00		Just the function addresses, without
	1C 00 00 00		the CALL prefix.
	2C 00 00 00

	On a 16-bit machine like the ones which originally ran FORTH the savings are even greater - 33%.

	[Historical note: If the execution model that FORTH uses looks strange from the following
	paragraphs, then it was motivated entirely by the need to save memory on early computers.
	This code compression isn't so important now when our machines have more memory in their L1
	caches than those early computers had in total, but the execution model still has some
	useful properties].

	Of course this code won't run directly any more.  Instead we need to write an interpreter
	which takes each pair of bytes and calls it.

	On an i386 machine it turns out that we can write this interpreter rather easily, in just
	two assembly instructions which turn into just 3 bytes of machine code.  Let's store the
	pointer to the next word to execute in the %esi register:

		08 00 00 00	<- We're executing this one now.  %esi is the _next_ one to execute.
	%esi -> 1C 00 00 00
		2C 00 00 00

	The all-important i386 instruction is called LODSL (or in Intel manuals, LODSW).  It does
	two things.  Firstly it reads the memory at %esi into the accumulator (%eax).  Secondly it
	increments %esi by 4 bytes.  So after LODSL, the situation now looks like this:

		08 00 00 00	<- We're still executing this one
		1C 00 00 00	<- %eax now contains this address (0x0000001C)
	%esi -> 2C 00 00 00

	Now we just need to jump to the address in %eax.  This is again just a single x86 instruction
	written JMP *(%eax).  And after doing the jump, the situation looks like:

		08 00 00 00
		1C 00 00 00	<- Now we're executing this subroutine.
	%esi -> 2C 00 00 00

	To make this work, each subroutine is followed by the two instructions 'LODSL; JMP *(%eax)'
	which literally make the jump to the next subroutine.

	And that brings us to our first piece of actual code!  Well, it's a macro.
*/

	.macro next
	ldr	x0, [NIP], #8	// load WORD from NIP, increment NIP
	ldr	x1, [x0]	// load CODEWORD (offset 0 of WORD)
	br	x1		// jump to CODEWORD
	.endm

/*	The macro is called next.  That's a FORTH-ism.  It expands to those two instructions.

	Every FORTH primitive that we write has to be ended by next.  Think of it kind of like
	a return.

	The above describes what is known as direct threaded code.

	To sum up: We compress our function calls down to a list of addresses and use a somewhat
	magical macro to act as a "jump to next function in the list".  We also use one register (%esi)
	to act as a kind of instruction pointer, pointing to the next function in the list.

	I'll just give you a hint of what is to come by saying that a FORTH definition such as:

	: quadruple double double ;

	actually compiles (almost, not precisely but we'll see why in a moment) to a list of
	function addresses for double, double and a special function called EXIT to finish off.

	At this point, REALLY EAGLE-EYED ASSEMBLY EXPERTS are saying "JONES, YOU'VE MADE A MISTAKE!".

	I lied about JMP *(%eax).

	INDIRECT THREADED CODE ----------------------------------------------------------------------

	It turns out that direct threaded code is interesting but only if you want to just execute
	a list of functions written in assembly language.  So quadruple would work only if double
	was an assembly language function.  In the direct threaded code, quadruple would look like:

		+------------------+
		| addr of double  --------------------> (assembly code to do the double)
		+------------------+                    next
	%esi ->	| addr of double   |
		+------------------+

	We can add an extra indirection to allow us to run both words written in assembly language
	(primitives written for speed) and words written in FORTH themselves as lists of addresses.

	The extra indirection is the reason for the brackets in jmp *(%eax).

	Let's have a look at how quadruple and double really look in FORTH:

	        : quadruple double double ;

		+------------------+
		| codeword         |		   : double dup + ;
		+------------------+
		| addr of double  ---------------> +------------------+
		+------------------+               | codeword         |
		| addr of double   |		   +------------------+
		+------------------+	   	   | addr of dup   --------------> +------------------+
		| addr of exit	   |		   +------------------+            | codeword      -------+
		+------------------+	   %esi -> | addr of +     --------+	   +------------------+   |
						   +------------------+	   |	   | assembly to    <-----+
						   | addr of exit     |    |       | implement dup    |
						   +------------------+	   |	   |	..	      |
									   |	   |    ..            |
									   |	   | next             |
									   |	   +------------------+
									   |
									   +-----> +------------------+
										   | codeword      -------+
										   +------------------+   |
										   | assembly to   <------+
										   | implement +      |
										   | 	..            |
										   | 	..            |
										   | next      	      |
										   +------------------+

	This is the part where you may need an extra cup of tea/coffee/favourite caffeinated
	beverage.  What has changed is that I've added an extra pointer to the beginning of
	the definitions.  In FORTH this is sometimes called the "codeword".  The codeword is
	a pointer to the interpreter to run the function.  For primitives written in
	assembly language, the "interpreter" just points to the actual assembly code itself.
	They don't need interpreting, they just run.

	In words written in FORTH (like quadruple and double), the codeword points to an interpreter
	function.

	I'll show you the interpreter function shortly, but let's recall our indirect
	jmp *(%eax) with the "extra" brackets.  Take the case where we're executing double
	as shown, and DUP has been called.  Note that %esi is pointing to the address of +

	The assembly code for dup eventually does a next.  That:

	(1) reads the address of + into %eax		%eax points to the codeword of +
	(2) increments %esi by 4
	(3) jumps to the indirect %eax			jumps to the address in the codeword of +,
							ie. the assembly code to implement +

		+------------------+
		| codeword         |
		+------------------+
		| addr of double  ---------------> +------------------+
		+------------------+               | codeword         |
		| addr of double   |		   +------------------+
		+------------------+	   	   | addr of dup   --------------> +------------------+
		| addr of exit	   |		   +------------------+            | codeword      -------+
		+------------------+	   	   | addr of +     --------+	   +------------------+   |
						   +------------------+	   |	   | assembly to    <-----+
					   %esi -> | addr of exit     |    |       | implement dup    |
						   +------------------+	   |	   |	..	      |
									   |	   |    ..            |
									   |	   | next             |
									   |	   +------------------+
									   |
									   +-----> +------------------+
										   | codeword      -------+
										   +------------------+   |
									now we're  | assembly to    <-----+
									executing  | implement +      |
									this	   | 	..            |
									function   | 	..            |
										   | next      	      |
										   +------------------+

	So I hope that I've convinced you that next does roughly what you'd expect.  This is
	indirect threaded code.

	I've glossed over four things.  I wonder if you can guess without reading on what they are?

	.
	.
	.

	My list of four things are: (1) What does "EXIT" do?  (2) which is related to (1) is how do
	you call into a function, ie. how does %esi start off pointing at part of QUADRUPLE, but
	then point at part of DOUBLE.  (3) What goes in the codeword for the words which are written
	in FORTH?  (4) How do you compile a function which does anything except call other functions
	ie. a function which contains a number like : DOUBLE 2 * ; ?

	THE INTERPRETER AND RETURN STACK ------------------------------------------------------------

	Going at these in no particular order, let's talk about issues (3) and (2), the interpreter
	and the return stack.

	Words which are defined in FORTH need a codeword which points to a little bit of code to
	give them a "helping hand" in life.  They don't need much, but they do need what is known
	as an "interpreter", although it doesn't really "interpret" in the same way that, say,
	Java bytecode used to be interpreted (ie. slowly).  This interpreter just sets up a few
	machine registers so that the word can then execute at full speed using the indirect
	threaded model above.

	One of the things that needs to happen when QUADRUPLE calls DOUBLE is that we save the old
	NIP ("instruction pointer") and create a new one pointing to the first word in DOUBLE.
	Because we will need to restore the old NIP at the end of DOUBLE (this is, after all, like
	a function call), we will need a stack to store these "return addresses" (old values of NIP).

	As you will have read, when reading the background documentation, FORTH has two stacks,
	an ordinary stack for parameters, and a return stack which is a bit more mysterious.  But
	our return stack is just the stack I talked about in the previous paragraph, used to save
	NIP when calling from a FORTH word into another FORTH word.

	In this FORTH, we are using x28 for the parameter stack. We will use another general-purpose
	register (x29, more commonly used as the "frame pointer") for our return stack.

	I've got two macros which just wrap up the details of using %ebp for the return stack.
	You use them as for example "PUSHRSP x1" (push x1 on the return stack) or "POPRSP x0"
	(pop top of return stack into x0).
*/

        // Return stack manipulation
	.macro PUSHRSP reg
	str	\reg, [RSP, #-8]!	// store at RSP-8, decrement RSP
	.endm

	.macro POPRSP reg
	ldr	\reg, [RSP], #8		// load from RSP, post-increment RSP
	.endm

        // Parameter stack manipulation
        .macro PUSHPSP reg
        str \reg, [PSP, #-8]!           // store at PSP-8, decrement PSP
        .endm

        .macro POPPSP reg
        ldr \reg, [PSP], #8             // load from PSP, post-increment PSP
        .endm

        .macro RESET_INPUT
        ldr     x2, =var_srcid
        str     xzr, [x2]
        ldr     x2, =var_inbuf
        ldr     x1, =buffer
        str     x1, [x2]
        ldr     x2, =var_to_in
        str     xzr, [x2]
        .endm

PSP	.req	x28	// parameter stack pointer
RSP	.req	x29	// return stack pointer
NIP	.req	x10	// next instruction pointer


/*
	And with that we can now talk about the interpreter.

	In FORTH the interpreter function is often called DOCOL (I think it means "DO COLON" because
	all FORTH definitions start with a colon, as in : DOUBLE DUP + ;

	The "interpreter" (it's not really "interpreting") just needs to push the old NIP (next
	instruction pointer) on the return stack and set NIP to the first word in the definition.
	Remember that we jumped to the function using the next macro?  Well a consequence of that is
	that conveniently x0 contains the address the word, so just by adding 8 to it we get the
	address of the first data word which is our new NIP.  Finally after setting up NIP, it just
	does next which causes that first word to run.

*/

/* DOCOL - the interpreter! */
	.text
	.align 3
docol:
	PUSHRSP	NIP		// push NIP on return stack
	add	NIP, x0, #8	// skip codeword, make NIP the first dataword
	next

/*
	Just to make this absolutely clear, let's see how DOCOL works when jumping from QUADRUPLE
	into DOUBLE:

		QUADRUPLE:
		+------------------+
		| codeword         |
		+------------------+		   DOUBLE:
		| addr of DOUBLE  ---------------> +------------------+
		+------------------+       %eax -> | addr of DOCOL    |
	%esi ->	| addr of DOUBLE   |		   +------------------+
		+------------------+	   	   | addr of DUP      |
		| addr of EXIT	   |		   +------------------+
		+------------------+               | etc.             |

	First, the call to DOUBLE calls DOCOL (the codeword of DOUBLE).  DOCOL does this:  It
	pushes the old %esi on the return stack.  %eax points to the codeword of DOUBLE, so we
	just add 4 on to it to get our new %esi:

		QUADRUPLE:
		+------------------+
		| codeword         |
		+------------------+		   DOUBLE:
		| addr of DOUBLE  ---------------> +------------------+
top of return	+------------------+       %eax -> | addr of DOCOL    |
stack points ->	| addr of DOUBLE   |	   + 4 =   +------------------+
		+------------------+	   %esi -> | addr of DUP      |
		| addr of EXIT	   |		   +------------------+
		+------------------+               | etc.             |

	Then we do next, and because of the magic of threaded code that increments %esi again
	and calls DUP.

	Well, it seems to work.

	One minor point here.  Because DOCOL is the first bit of assembly actually to be defined
	in this file (the others were just macros), and because I usually compile this code with the
	text segment starting at address 0, DOCOL has address 0.  So if you are disassembling the
	code and see a word with a codeword of 0, you will immediately know that the word is
	written in FORTH (it's not an assembler primitive) and so uses DOCOL as the interpreter.

	STARTING UP ----------------------------------------------------------------------

	Now let's get down to nuts and bolts.  When we start the program we need to set up
	a few things like the return stack.  But as soon as we can, we want to jump into FORTH
	code (albeit much of the "early" FORTH code will still need to be written as
	assembly language primitives).

	This is what the set up code does.  Does a tiny bit of house-keeping, sets up the
	separate return stack (NB: Linux gives us the ordinary parameter stack already), then
	immediately jumps to a FORTH word called QUIT.  Despite its name, QUIT doesn't quit
	anything.  It resets some internal state and starts reading and interpreting commands.
	(The reason it is called QUIT is because you can call QUIT from your own FORTH code
	to "quit" your program and go back to interpreting).
*/

	.text
	.align 3
	.global _forth_start
_forth_start:
        bl      _con_init               // initialize serial port

        ldr     PSP, =data_stack_top    // initialize parameter stack
        ldr     RSP, =return_stack_top  // initialize return stack

        mov     x0, #'F'                // emit an 'F' to show we're connected
        bl      _con_out

        RESET_INPUT
        ldr     x0, =var_inbuf
        ldr     x1, =jonesforth_src
        str     x1, [x0]
        ldr     x0, =var_srclen
        ldr     x1, =jonesforth_len
        str     x1, [x0]
        ldr     x0, =var_to_in
        str     xzr, [x0]

	ldr	NIP, =cold_start        // initialize interpreter
	next                            // run interpreter

	.section .rodata
        .align 3
cold_start:
	.quad   interpret
warm_start:
        .quad   quit

/*
        EXCEPTION RECOVERY -----------------------------------------------------------------

        We get here from the CPU's exception table. We do just enough setup to report the error on
        the serial console and reset some core variables, then we go back to the beginning.

        TODO - Print the exception type and ESR (stored in var_exception and var_excode by the
        exception entry itself. See exceptions.S)

        TODO - Add a counter for consecutive restarts. After N retries, there's probably an error
        in the init file itself. Drop to a naked prompt instead of repeating the bootloop.

*/

        .text
        .global  _forth_restart
_forth_restart:
        ldr     PSP, =data_stack_top    // get the top of the parameter stack

        ldr     x0, =var_state          // reset state to 0
        mov     x1, #0
        str     x1, [x0]

        ldr     x0, =var_here           // reset the dictionary to data
        ldr     x1, =data_segment
        str     x1, [x0]

        ldr     x0, =var_latest         // reset latest to last defined word
        ldr     x1, =name_execute
        str     x1, [x0]

        ldr     x0, =var_s0             // reset pstack TOS
        ldr     x1, =data_stack_top
        str     x1, [x0]

        ldr     x0, =var_base           // reset base to decimal
        mov     x1, #10
        str     x1, [x0]

        ldr     x0, =var_echo           // reset echo to off
        mov     x1, #0
        str     x1, [x0]

        ldr     x0, =inbuf              // reset to keyboard input
        ldr     x1, =buffer
        str     x1, [x0]

        ldr     x0, =srcid
        str     xzr, [x0]

        ldr     x1, =crnl
        mov     x2, #2
        bl      _tell

        ldr     x1, =excmsg
        mov     x2, #excmsgend-excmsg
        bl      _tell

        ldr     x1, =crnl
        mov     x2, #2
        bl      _tell

        b       _forth_start

        .section .rodata
        .align 3
excmsg: .ascii "CORE ABORT!"
excmsgend:


//	BUILT-IN WORDS ----------------------------------------------------------------------
//
//	Remember our dictionary entries (headers)?  Let's bring those together with the codeword
//	and data words to see how : DOUBLE DUP + ; really looks in memory.
//
//	  pointer to previous word
//	   ^
//	   |
//	+--|------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
//	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
//	+---------+---+---+---+---+---+---+---+---+------------+--|---------+------------+------------+
//         ^       len                         pad  codeword      |
//	   |							  V
//	  LINK in next word				points to codeword of DUP
//
//	Initially we can't just write ": DOUBLE DUP + ;" (ie. that literal string) here because we
//	don't yet have anything to read the string, break it up at spaces, parse each word, etc. etc.
//	So instead we will have to define built-in words using the GNU assembler data constructors
//	(like .int, .byte, .string, .ascii and so on -- look them up in the gas info page if you are
//	unsure of them).
//
//	The long way would be:
//	  .int <link to previous word>
//	  .byte 6		// len
//	  .ascii "DOUBLE"	// string
//	  .byte 0		// padding
//DOUBLE: .int DOCOL		// codeword
//	  .int DUP		// pointer to codeword of DUP
//	  .int PLUS		// pointer to codeword of +
//	  .int EXIT		// pointer to codeword of EXIT
//
//	That's going to get quite tedious rather quickly, so here I define an assembler macro
//	so that I can just write:
//
//	defword "DOUBLE",6,,DOUBLE
//	.int DUP,PLUS,EXIT
//
//	and I'll get exactly the same effect.
//
//	Don't worry too much about the exact implementation details of this macro - it's complicated!

        // Flags - these are discussed later.
	.set f_immed,0x80
	.set f_hidden,0x20

        // Store the chain of links
	// .set link,0

	.macro defword name, namelen, flags=0, label, link
	.section .rodata
	.align 3
	.global name_\label
name_\label :
	.quad name_\link                // link word
	.byte \flags                    // flags byte
	.byte \namelen           	// name length byte
	.ascii "\name"                  // the name
	.rept 30-\namelen		// pad the name to 30 bytes long with commas
	.ascii ","
	.endr
	.align 	3                       // padding to next 8 byte boundary
	.global \label
\label :
	.quad docol                     // codeword - the interpreter
	// list of word pointers follows
	.endm

//	Similarly I want a way to write words written in assembly language.  There will quite a few
//	of these to start with because, well, everything has to start in assembly before there's
//	enough "infrastructure" to be able to start writing FORTH words, but also I want to define
//	some common FORTH words in assembly language for speed, even though I could write them in FORTH.
//
//	This is what DUP looks like in memory:
//
//	  pointer to previous word
//	   ^
//	   |
//	+--|------+---+---+---+---+---+---+---+---+------------+
//	| LINK    | 3 | D | U | P | 0 | 0 | 0 | 0 | code_DUP -----------------> points to the assembly
//	+---------+---+---+---+---+---+---+---+---+------------+                code used to write DUP,
//           ^       len                            codeword			which ends with next.
//           |
//	    LINK in next word
//
//      The extra 0's after the name are padding required by the ARM CPU
//      to make the code words align to a 8-byte boundary.
//
//	Again, for brevity in writing the header I'm going to write an assembler macro called defcode.

	.macro defcode name, namelen, flags=0, label, link
	.section .rodata
	.align 3
	.global name_\label
name_\label :
	.quad name_\link                // link word
	.byte \flags			// insert flag
	.byte \namelen			// insert name length
	.ascii "\name"			// insert name
	.rept 30-\namelen		// pad name to 30 bytes with commas
	.ascii ","
	.endr
	.align 3
	.global \label
\label :
	.quad code_\label
	.text
	.pool
	.global code_\label
        .type code_\label,%function
code_\label :
	// assembler code follows
	.endm

/*
	Now some easy FORTH primitives.  These are written in assembly for speed.  If you understand
	assembly language then it is worth reading these.  However if you don't understand assembly
	you can skip the details.
*/

        .align 3
name_0: .quad 0

	// DROP (a -- )
	defcode "drop",4,,drop,0
	add	PSP, PSP, #8
	next

	// SWAP (a b -- b a)
	defcode "swap",4,,swap,drop
	ldr	x0, [PSP]
	ldr	x1, [PSP, #8]
	str	x0, [PSP, #8]
	str	x1, [PSP]
	next

	// DUP (a -- a a)
	defcode "dup",3,,dup,swap
	ldr	x0, [PSP]
	PUSHPSP	x0
	next

	// OVER (a b -- a b a)
	defcode "over",4,,over,dup
	ldr	x0, [PSP, #8]           // get the second element of stack
	PUSHPSP	x0                      // and push it on top
	next

	// ROT ( n1 n2 n3 -- n2 n3 n1 )
	defcode "rot",3,,rot,over
        POPPSP  x3                      // n3
        POPPSP  x2                      // n2
        POPPSP  x1                      // n1

        PUSHPSP x2                      // n2
        PUSHPSP x3                      // n3
        PUSHPSP x1                      // n1
	next

	// -ROT ( n1 n2 n3 -- n3 n1 n2 )
	defcode "-rot",4,,nrot,rot
        POPPSP  x3                      // n3
        POPPSP  x2                      // n2
        POPPSP  x1                      // n1

        PUSHPSP x3                      // n3
        PUSHPSP x1                      // n1
        PUSHPSP x2                      // n2
	next

        defcode "?dup",4,,qdup,nrot     // duplicate top of stack if it is non-zero
        ldr     x0, [PSP]
        cmp     x0, #0
        beq     1f
        PUSHPSP x0
1:      next

        defcode "1+",2,,incr,qdup
        POPPSP  x0
        add     x0, x0, #1
        PUSHPSP x0
        next

        defcode "1-",2,,decr,incr
        POPPSP  x0
        sub     x0, x0, #1
        PUSHPSP x0
        next

        defcode "4+",2,,incr4,decr
        POPPSP  x0
        add     x0,x0,#4
        PUSHPSP x0
        next

        defcode "4-",2,,decr4,incr4
        POPPSP  x0
        sub     x0,x0,#4
        PUSHPSP x0
        next

	// + ( a b -- a+b )
	defcode "+",1,,add,decr4
        POPPSP  x1
        POPPSP  x0
	add	x0, x1, x0
	PUSHPSP	x0
	next

        // - ( a b -- a-b )
	defcode "-",1,,sub,add
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	sub	x0, x0, x1              // x0 < a - b
	PUSHPSP	x0
	next

	// * ( a b -- a*b )
	defcode "*",1,,mul,sub
        POPPSP  x1
        POPPSP  x0
	mul	x0, x1, x0
	PUSHPSP	x0
	next

        // << ( x u -- x<<u )
        defcode "lshift",6,,lshift,mul
        POPPSP  x0                      // x0 <- u
        POPPSP  x1                      // x1 <- x
        lsl     x1, x1, x0
        PUSHPSP	x1
        next

        // >> ( x u -- x>>u )
        defcode "rshift",6,,rshift,lshift
        POPPSP  x0                      // x0 <- u
        POPPSP  x1                      // x1 <- x
        lsr     x1, x1, x0
        PUSHPSP x1
        next

//      In this FORTH, only /MOD is primitive.  Later we will define
//      the / and MOD words in terms of the primitive /MOD.

	// /MOD (a b -- a%b a/b)
	defcode "/mod",4,,divmod,rshift
        POPPSP  x2                      // x2 <- b
        POPPSP  x1                      // x1 <- a
        sdiv    x0, x1, x2              // x0 = a / b
        msub    x3, x0, x2, x1          // x3 = a - (x0 * b)
        PUSHPSP x3                      // push remainder
        PUSHPSP x0                      // push quotient
	next

// for debugging, use this for gdb breakpoints
// In gdb, run `b code_brk`
        defcode "brk",3,,brk,divmod
        next

// 	Lots of comparison operations.
//
//	ANS FORTH says that the comparison words should return all (binary) 1's for
//	TRUE and all 0's for FALSE.  However this is a bit of a strange convention
//	so this FORTH breaks it and returns the more normal (for C programmers ...)
//	1 meaning TRUE and 0 meaning FALSE.

	// = (a b -- a=b)
	defcode "=",1,,equ,brk
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, ne        // x0 <- (a != b) ? 0 : 1
	PUSHPSP	x0
	next

	// <> (a b -- a<>b)
	defcode "<>",2,,nequ,equ
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, eq        // x0 <- (a == b) ? 0 : 1
	PUSHPSP	x0
	next

	// < (a b -- a<b)
	defcode "<",1,,lt,nequ
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, ge        // x0 <- (a >= b) ? 0 : 1
	PUSHPSP	x0
	next

	// > (a b -- a>b)
	defcode ">",1,,gt,lt
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, le        // x0 <- (a <= b) ? 0 : 1
	PUSHPSP	x0
	next

	// <= (a b -- a<=b)
	defcode "<=",2,,le,gt
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, gt        // x0 <- (a > b) ? 0 : 1
	PUSHPSP	x0
	next

	// >= (a b -- a>=b)
	defcode ">=",2,,ge,le
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	cmp	x0, x1                  // test a vs b
        csinc   x0, xzr, xzr, lt        // x0 <- (a < b) ? 0 : 1
	PUSHPSP	x0
	next

        // 0= (a -- a == 0)
        defcode "0=",2,,zeroeq,ge
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, ne
        PUSHPSP x0
        next

        // 0<> (a -- a <> 0)
        defcode "0<>",3,,zerone,zeroeq
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, eq
        PUSHPSP x0
        next

        // 0< (a -- a<0)
        defcode "0<",2,,zlt,zerone
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, ge
        PUSHPSP x0
        next

        // 0> (a -- a>0)
        defcode "0>",2,,zgt,zlt
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, le
        PUSHPSP x0
        next

        // 0<= (a -- a<=0)
        defcode "0<=",3,,zle,zgt
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, gt
        PUSHPSP x0
        next

        // 0>= (a -- a>=0)
        defcode "0>=",3,,zge,zle
        POPPSP  x0
        cmp     x0, xzr
        csinc   x0, xzr, xzr, lt
        PUSHPSP x0
        next

	// AND (a b -- a&b)
	defcode "and",3,,and,zge
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	and	x0, x1, x0
	PUSHPSP	x0
	next

	// OR (a b -- a|b)
	defcode "or",2,,or,and
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	orr	x0, x1, x0
	PUSHPSP	x0
	next

	// XOR (a b -- a^b)
	defcode "xor",3,,xor,or
        POPPSP  x1                      // x1 <- b
        POPPSP  x0                      // x0 <- a
	eor	x0, x1, x0
	PUSHPSP	x0
	next

	// INVERT (a -- ~a)
	defcode "invert",6,,invert,xor
	ldr	x0, [PSP]
	mvn	x0, x0
	str	x0, [PSP]
	next

/*
	RETURNING FROM FORTH WORDS ----------------------------------------------------------------------

	Time to talk about what happens when we EXIT a function.  In this diagram QUADRUPLE has called
	DOUBLE, and DOUBLE is about to exit (look at where NIP is pointing):

		QUADRUPLE
		+------------------+
		| codeword         |
		+------------------+		   DOUBLE
		| addr of DOUBLE  ---------------> +------------------+
		+------------------+               | codeword         |
		| addr of DOUBLE   |		   +------------------+
		+------------------+	   	   | addr of DUP      |
		| addr of EXIT	   |		   +------------------+
		+------------------+	   	   | addr of +        |
						   +------------------+
					    NIP -> | addr of EXIT     |
						   +------------------+

	What happens when the + function does next?  Well, the following code is executed.
*/

	defcode "exit",4,,exit,invert
	POPRSP	NIP
	next

/*
	EXIT gets the old NIP which we saved from before on the return stack, and puts it in NIP.
	So after this (but just before next) we get:

		QUADRUPLE
		+------------------+
		| codeword         |
		+------------------+		   DOUBLE
		| addr of DOUBLE  ---------------> +------------------+
		+------------------+               | codeword         |
	 NIP ->	| addr of DOUBLE   |		   +------------------+
		+------------------+	   	   | addr of DUP      |
		| addr of EXIT	   |		   +------------------+
		+------------------+	   	   | addr of +        |
						   +------------------+
						   | addr of EXIT     |
						   +------------------+

	And next just completes the job by, well, in this case just by calling DOUBLE again :-)

	LITERALS ----------------------------------------------------------------------

	The final point I "glossed over" before was how to deal with functions that do anything
	apart from calling other functions.  For example, suppose that DOUBLE was defined like this:

	: DOUBLE 2 * ;

	It does the same thing, but how do we compile it since it contains the literal 2?  One way
	would be to have a function called "2" (which you'd have to write in assembler), but you'd need
	a function for every single literal that you wanted to use.

	FORTH solves this by compiling the function using a special word called LIT:

	+---------------------------+-------+-------+-------+-------+-------+
	| (usual header of DOUBLE)  | DOCOL | LIT   | 2     | *     | EXIT  |
	+---------------------------+-------+-------+-------+-------+-------+

	LIT is executed in the normal way, but what it does next is definitely not normal.  It
	looks at NIP (which now points to the number 2), grabs it, pushes it on the stack, then
	manipulates NIP in order to skip the number as if it had never been there.

*/

	defcode "lit",3,,lit,exit
	ldr	x0, [NIP], #8	// load word from NIP, then increment NIP
	PUSHPSP	x0		// push the word
	next

/*
	MEMORY ----------------------------------------------------------------------

	As important point about FORTH is that it gives you direct access to the lowest levels
	of the machine.  Manipulating memory directly is done frequently in FORTH, and these are
	the primitive words for doing it.
*/

	// ! (value address -- ) M[address] = value
	defcode "!",1,,store,lit
        POPPSP  x0
        POPPSP  x1
	str	x1, [x0]
	next

	// // (address -- value) value = M[address]
	defcode "@",1,,fetch,store
	POPPSP	x0
	ldr	x1, [x0]
	PUSHPSP	x1
	next

	// +! (value address -- ) M[address] += value
	defcode "+!",2,,addstore,fetch
        POPPSP  x0
        POPPSP  x1
	ldr	x2, [x0]
	add	x2, x2, x1
	str	x2, [x0]
	next

	// -! (value address -- ) M[address] -= value
	defcode "-!",2,,substore,addstore
        POPPSP  x0
        POPPSP  x1
	ldr	x2, [x0]
	sub	x2, x2, x1
	str	x2, [x0]
	next

/*

	! and @ (STORE and FETCH) store 64-bit words.  It's also useful to be able to read and write bytes
	so we also define standard words C@ and C!.

*/

	defcode "c!",2,,storebyte,substore
	POPPSP	x0		// address
	POPPSP	x1		// value
	strb	w1, [x0]	// store
	next

	defcode "c@",2,,fetchbyte,storebyte
	POPPSP	x0		// address
	ldrb	w1, [x0]	// load
	PUSHPSP	x1
	next

/* C@C! is a useful byte copy operation */
	defcode "c@c!",4,,ccopy,fetchbyte
	ldr	x0, [PSP, #8]	// source address
	ldr	x1, [PSP]	// destination address
	ldrb	w2, [x0], #1	// load and increment
	strb	w2, [x1], #1	// store and increment
	str	x0, [PSP, #8]	// update source
	str	x1, [PSP]	// update destination
	next

/* and CMOVE is a block copy operation. */
	defcode "cmove",5,,cmove,ccopy
	POPPSP	x0		// length
	POPPSP	x1		// destination address
	POPPSP	x2		// source address
	cmp	x0, #0
        b.eq    2f
1:      ldrb	w3, [x2], #1	// load, increment r2
	strb	w3, [x1], #1	// store, increment r3
	subs	x0, x0, #1	// decrement counter
	b.gt	1b		// until length = 0
2:
	next

/*

        For reading and writing hardware registers, it's necessary to have 32-bit wide
        operations. Otherwise the ARM processor will trigger an alignment fault if we try to use a
        64-bit write on an address that is not 64-bit aligned... such as any hardware register with
        a 0x04 offset.

*/

        // ( n a -- )
	defcode "w!",2,,storeword,cmove
	POPPSP	x0		// address
	POPPSP	x1		// value
	str	w1, [x0]	// store
	next

	defcode "w@",2,,fetchword,storeword
	POPPSP	x0		// address
	ldr	w1, [x0]        // load
	PUSHPSP	x1
	next

/*
	BUILT-IN VARIABLES ----------------------------------------------------------------------

	These are some built-in variables and related standard FORTH words.  Of these, the only one that we
	have discussed so far was LATEST, which points to the last (most recently defined) word in the
	FORTH dictionary.  LATEST is also a FORTH word which pushes the address of LATEST (the variable)
	on to the stack, so you can read or write it using @ and ! operators.  For example, to print
	the current value of LATEST (and this can apply to any FORTH variable) you would do:

	LATEST @ . CR

	To make defining variables shorter, I'm using a macro called defvar, similar to defword and
	defcode above.  (In fact the defvar macro uses defcode to do the dictionary header).
*/

	.macro defvar name, namelen, flags=0, label, link, initial=0
	defcode \name,\namelen,\flags,\label,\link
	ldr	x0, =var_\name	// load address
	PUSHPSP	x0		// push address
	next
	.data
	.align 3
        .global var_\name
var_\name :
	.quad \initial
	.endm

/*
	The built-in variables are:

	state		Is the interpreter executing code (0) or compiling a word (non-zero)?
	latest		Points to the latest (most recently defined) word in the dictionary.
	here		Points to the next free byte of memory.  When compiling, compiled words go here.
	s0		Stores the address of the top of the parameter stack.
	base		The current base for printing and reading numbers.
        echo            Echo keys as they are received
        pong            Debug-print each word as it is interpreted

*/

	defvar "state",5,,state,fetchword
	defvar "here",4,,here,state,data_segment
	defvar "latest",6,,latest,here,name_execute
	defvar "s0",2,,sz,latest,data_stack_top
	defvar "base",4,,base,sz,10
        defvar "echo",4,,echo,base,1
        defvar "exception",9,,exception,echo
        defvar "excode",6,,excode,exception
        defvar "in0",3,,in0,excode,buffer
        defvar "inbuf",5,,inbuf,in0,buffer
        defvar "srclen",6,,srclen,inbuf
        defvar "srcid",5,,srcid,srclen

        .global var_exception
        .global var_excode

        // this one is "hand rolled" because "var_>in" is not a valid assembly label
	defcode ">in",3,,to_in,srcid
	ldr	x0, =var_to_in	// load address
	PUSHPSP	x0		// push address
	next
	.data
	.align 3
        .global var_to_in
var_to_in:
	.quad 0


/*
	BUILT-IN CONSTANTS ----------------------------------------------------------------------

	It's also useful to expose a few constants to FORTH.  When the word is executed it pushes a
	constant value on the stack.

	The built-in constants are:

	VERSION		Is the current version of this FORTH.
	R0		The address of the top of the return stack.
	DOCOL		Pointer to DOCOL.
	F_IMMED		The IMMEDIATE flag's actual value.
	F_HIDDEN	The HIDDEN flag's actual value.

*/

	.macro defconst name, namelen, flags=0, label, link, value
	defcode \name,\namelen,\flags,\label,\link
	ldr	x0, =\value
	PUSHPSP	x0
	next
	.endm

	defconst "version",7,,version,to_in,JONES_VERSION
	defconst "r0",2,,rz,version,return_stack_top
	defconst "docol",5,,__docol,rz,docol
	defconst "f_immed",7,,__f_immed,__docol,f_immed
	defconst "f_hidden",8,,__f_hidden,__f_immed,f_hidden
        defconst "lastcell",8,,lastcell,__f_hidden,LASTCELL
        defconst "peripherals",11,,peripherals,lastcell,PERIPHERALS
        defconst "charrom",7,,charrom,peripherals,char_rom

        .macro embed src,name,namelen,label,link
        defcode \name,\namelen,,\label,\link
        ldr     x0, =\label\()_src
        PUSHPSP x0
        ldr     x0, =\label\()_len
        PUSHPSP x0
        next

        .section .rodata
        \label\()_src: .incbin "\src"
        \label\()_src_end:
        .set  \label\()_len,\label\()_src_end - \label\()_src

        .text
        .endm

        embed   "jonesforth.f","jonesforth",10,jonesforth,charrom
        embed   "mailbox.f","mailbox",7,mailbox,jonesforth
        embed   "test.f","test",4,test,mailbox
        embed   "assembler.f","assembler",9,assembler,test
        embed   "video.f","video",5,video,assembler
        embed   "sdcard.f","sdcard",6,sdcard,video
        embed   "direct_thread.f","direct-thread",13,direct_thread,sdcard

	/* This is the instruction template for all of our direct word calls. */

test_template:
	add	x3, x10, #42
	add	w3, w10, #42
	sub	x3, x10, #42
	sub	w3, w10, #42

call_template:
	adr     x30,#24 	// 0:  Load return address
	adr	x17,#12		// 4:  Load addr of f address
	ldr	x17,[x17]     	// 8:  Load f address
	br	x17          	// 12: Branch to f
call_template_end:

ret_template:
	next
ret_template_end:
	
	/* Plain old assembly language function. */
	defconst "say-msg",7,,__say_msg,direct_thread,_saymsg

	/* Instruction templates, used by compiler. */

	defconst "call-template",13,,__call_template,__say_msg,call_template
	defconst "call-template-len",17,,__call_template_len,__call_template,(call_template_end-call_template)/4
	defconst "ret-template",12,,__ret_template,__call_template_len,ret_template
	defconst "ret-template-len",16,,__ret_template_len,__ret_template,(ret_template_end-ret_template)/4
/*
	RETURN STACK ----------------------------------------------------------------------

	These words allow you to access the return stack.  Recall that the register RSP always points to
	the top of the return stack.
*/

	defcode ">r",2,,tor,__ret_template_len
	POPPSP	x0                      // pop parameter stack into x0
	PUSHRSP	x0                      // and push it onto the return stack
	next

	defcode "r>",2,,fromr,tor
	POPRSP	x0                      // pop return stack into x0
	PUSHPSP	x0                      // and push it onto the parameter stack
	next

	defcode "rsp@",4,,rspfetch,fromr
	PUSHPSP	RSP                     // get the top of the return stack
	next

	defcode "rsp!",4,,rspstore,rspfetch
	POPPSP	RSP                     // set the top of the return stack
	next

	defcode "rdrop",5,,rdrop,rspstore
	add	RSP, RSP, #8            // drop the top of the return stack
	next

/*
	PARAMETER (DATA) STACK ----------------------------------------------------------------------

	These functions allow you to manipulate the parameter stack.  Recall that Linux sets up the parameter
	stack for us, and it is accessed through x28.
*/

	defcode "dsp@",4,,dspfetch,rdrop
	mov	x0, PSP
	PUSHPSP	x0
	next

	defcode "dsp!",4,,dspstore,dspfetch
	POPPSP	x0
	mov	PSP, x0
	next

/*
	INPUT AND OUTPUT ----------------------------------------------------------------------

	These are our first really meaty/complicated FORTH primitives.  I have chosen to write them in
	assembler, but surprisingly in "real" FORTH implementations these are often written in terms
	of more fundamental FORTH primitives.  I chose to avoid that because I think that just obscures
	the implementation.  After all, you may not understand assembler but you can just think of it
	as an opaque block of code that does what it says.

	Let's discuss input first.

        KEY reads a single character from the console. In previous versions, KEY was used by all the
        parsing words. However, this makes it hard to work with other input sources. We're now using
        an input system more similar to a Forth-2012 standard. KEY always reads from the interactive
        console. Parsing words (`word` and `parse`) look at the "current input source" which _might_
        be from the keyboard or might be from a string (via `evaluate`) or even a file ... whenever
        we implement files.

*/

        defcode "key",3,,key,dspstore   // ( -- key)
	bl	_con_in
	PUSHPSP	x0
	next

/*

        SERIAL PORT ----------------------------------------------------------------------

*/

	defcode "<con",4,,con_in,key    // ( -- key )
        PUSHPSP x1                      // save this register
        bl      _con_in
        POPPSP  x1
        PUSHPSP x0
        next
_con_in:                                // return char in x0
        // wait for data available
        ldr     x1, =UART_FR            // address of flags register
1:      ldr     w0, [x1]                // get flags
        ands    w0, w0, #(1<<4)         // check receive_fifo_empty bit
        bne     1b

        // data is available
        ldr     x1, =UART_DR            // address of data register
        ldr     w0, [x1]                // get data
        and     w0, w0, #0xff           // keep lower byte
        ret


        .global _con_out
        defcode ">con",4,,con_out,con_in // ( byte -- )
        POPPSP  x0                      // x0 <- byte to write
        bl      _con_out
        next
_con_out:                               // take char in x0
        PUSHPSP x1                      // preserve x1
        PUSHPSP x2                      // preserve x2
        // wait for space available
        ldr     x1, =UART_FR            // address of flags register
1:      ldr     w2, [x1]                // get flags
        ands    w2, w2, #(1<<5)         // check transmit_fifo_full bit
        bne     1b

        // space is available
        ldr     x1, =UART_DR            // address of data register
        str     w0, [x1]                // write the data byte
        POPPSP  x2                      // restore x2
        POPPSP  x1                      // restore x1
        ret

_con_init:
        // set GPIO 14 & 15 to output
        ldr     x1, =GPFSEL1            // Address of GPFSEL1 register
        ldr     w0, [x1]
        bic     w0, w0, #(7 << 12)      // clear bits 12 - 14 (fsel for pin 14)
        bic     w0, w0, #(7 << 15)      // clear bits 15 - 17 (fsel for pin 15)
        orr     w0, w0, #(4 << 12)      // 0b100 = Alt0 for pin 14
        orr     w0, w0, #(4 << 15)      // 0b100 = Alt0 for pin 15
        str     w0, [x1]                // write the register

        // enable GPIO 14 & 15
        ldr     x1, =GPPUD              // Address of GPPUD register
        str     wzr, [x1]               // zero it to set "float" status

        movz    x0, #150                // we need to spin 150 cycles
1:      subs    x0, x0, #1
        bne     1b

        ldr     x2, =GPPUDCLK0          // Address of GPPUDCLK0 register
        mov     w0, #(1 << 14) | (1 << 15)
        str     w0, [x2]                // clock in the 'float' for pins 14 & 15

        movz    x0, #150                // we need to spin another 150 cycles
2:      subs    x0, x0, #1
        bne     2b

        str     wzr, [x2]               // deassert all in GPPUDCLK0

        // turn off uart while initializing
        ldr     x1, =UART_CR            // Address of CR
        str     wzr, [x1]               // zero it

        // flush the xmit fifo
        ldr     x2, =UART_LCRH          // Address of LCHR (in x2 so we can use it later)
        str     wzr, [x2]               // zero it (disables fifos)

        // clear all pending interrupts
        ldr     x1, =UART_ICR           // Address of ICR
        str     wzr, [x1]               // zero it

        // set the baud rate, 8N1 and FIFO disabled.
        // use clock divisor 26.0417 to get 115,200 baud
        ldr     x1, =UART_IBRD          // Address of IBRD
        movz    w0, #0x001a             // integer part of 26.0417 - the clock divisor
        str     w0, [x1]                // set integer part
        ldr     x1, =UART_FBRD          // Address of FBRD
        movz    w0, #0x001b             // fractional part of clock divisor
        str     w0, [x1]                // set fractional part
        movz    w0, #(3 << 5)           // 8 bits word, no stop bits, even parity
        str     w0, [x2]                // set LCRH

        // disable interrupts
        ldr     x1, =UART_IMSC          // Address of IMSC register
        str     wzr, [x1]               // zero it

        // enable the uart
        ldr     x1, =UART_CR            // Address of control register
        movz    w0, #0x301              // xmit enable, recv enable, uart enable
        str     w0, [x1]                // enable the uart
        ret


	.data
	.align 3
currkey:
	.quad buffer		// Current place in input buffer (next character to read).
bufftop:
	.quad buffer		// Last valid data in input buffer + 1.

/*

	By contrast, output is much simpler.  The FORTH word EMIT writes out a single byte to stdout.
        The kernel must supply a routine that takes a single byte in w0 and outputs it. This routine
        must be linked as _forth_putch.

*/

        // ( ch -- ) write a byte to output
	defcode "emit",4,,emit,con_in
        POPPSP	x0
        bl      _con_out
	next

/*
	Back to input, WORD is a FORTH word which reads the next full word of input.

        WORD is a "parsing word". That means it doesn't get all of its input from the stack.
        Instead it parses through an input buffer that was either filled with `refill` or supplied
        by another input source (like `evaluate`). WORD leaves the address and length of the next
        word on the stack. This address may or may not be inside the input buffer.

        A zero length indicates no word is available from the input source.

        If WORD encounters a backslash before any non-blank character, it consumes everything to the
        next newline character. (I'm not 100% convinced this is the right place to do this.)

        WORD updates >in with the index in the input buffer of the next character _after_ the word
        it just read.

	What it does in detail is that it first skips any blanks (spaces, tabs, newlines and so on).
	Then it calls KEY to read characters into an internal buffer until it hits a blank.  Then it
	calculates the length of the word it read and returns the address and the length as
	two words on the stack (with the length at the top of stack).

	Notice that WORD has a single internal buffer which it overwrites each time (rather like
	a static C string).  Also notice that WORD's internal buffer is 1024 bytes long and
	there is NO checking for overflow.  30 bytes happens to be the maximum length of a
	FORTH word that we support, and that is what WORD is used for: to read FORTH words when
	we are compiling and executing code.  The returned strings are
	not NUL-terminated.

        Note also that WORD's buffer is shared with PARSE, so a call to WORD invalidates the last
        PARSE result and vice versa.

	Start address+length is the normal way to represent strings in FORTH (not ending in an
	ASCII NUL character as in C), and so FORTH strings can contain any character including NULs
	and can be any length.

	WORD is not suitable for just reading strings (eg. user input) because of all the above
	peculiarities and limitations.

*/

	defcode "word",4,,word,emit
	bl _word
	PUSHPSP	x0			// address
	PUSHPSP	x1			// length
	next
_word:
	// WORD () (address: x0, length: x1)
        PUSHPSP x6
        PUSHPSP x5
        PUSHPSP x4
        PUSHPSP lr

        // load x4 with address of next character in buffer
        ldr     x4, =var_inbuf          // input buffer addr
        ldr     x4, [x4]
        mov     x6, x4
        ldr     x0, =var_to_in
        ldr     x1, [x0]
        add     x4, x4, x1

        // load x6 with the address of the last source character
        ldr     x0, =var_srclen
        ldr     x1, [x0]
        add     x6, x6, x1

        // if input exhausted, return false
        cmp     x4, x6
        bgt     5f

        // load x5 with address of the word buffer
	ldr	x5, =word_buffer

1:      // skip blanks and check for comment line
        ldrb    w0, [x4], #1

        cmp     x4, x6                  // input exhausted
        bgt     5f                      // got nothing

	cmp	x0, #'\\'		// == \?
	beq	4f			// skip comment
	cmp	x0, #' '		// <= ' '?
	ble	1b			// skip all blanks and keep looking

2:	// store character, increment pointer
        strb	w0, [x5], #1
        ldrb    w0, [x4], #1

        // if input exhausted, return whatever we've got
        cmp     x4, x6
        bgt     6f

	cmp	w0, #' '		// > ' '?
	bgt	2b			// keep reading
        b       6f

4:      // consume til newline
        ldrb    w0, [x4], #1

        // if input exhausted while in a comment, there's no word
        cmp     x4, x6
        bgt     5f

	cmp	w0, #'\n'		// eol?
	bne	4b			// no, keep looking
	b	1b

5:      ldr     x5, =word_buffer        // this will make the length 0 later

6:      // update >in and return
        ldr     x0, =var_inbuf
        ldr     x0, [x0]
        sub     x1, x4, x0
        ldr     x0, =var_to_in
        str     x1, [x0]

        ldr     x0, =word_buffer        // address
        sub     x1, x5, x0              // length

        POPPSP  lr
        POPPSP  x4
        POPPSP  x5
        POPPSP  x6
        ret

	.data
        .global word_buffer
word_buffer:
	.space 1024

/*

        The next parsing word is `parse`. It is similar to `word` but treats leading delimiters a
        bit differently. The major difference is that `word` skips leading delimiters, `parse` does
        not.

        Unlike `word`, `parse` returns a substring of the input buffer.

*/

        defcode "parse",5,,parse,word
        POPPSP  x2                      // delimiter
        bl      _parse
	PUSHPSP	x0			// address
	PUSHPSP	x1			// length
        next
_parse:
	// WORD () (address: x0, length: x1)
        PUSHPSP x6
        PUSHPSP x5
        PUSHPSP x4
        PUSHPSP lr

        // load x4 with address of next character in buffer
        ldr     x4, =var_inbuf          // input buffer addr
        ldr     x4, [x4]
        mov     x6, x4
        ldr     x0, =var_to_in
        ldr     x1, [x0]
        add     x4, x4, x1

        // load x5 with address of the word budffer
        ldr     x5, =word_buffer

        // load x6 with the address of the last source character
        ldr     x0, =var_srclen
        ldr     x1, [x0]
        add     x6, x6, x1

        // if input exhausted, return false
        cmp     x4, x6
        bgt     6f

1:      // fetch and examine next character
        ldrb    w0, [x4], #1            // get next character

        cmp     x4, x6                  // input exhausted?
        bgt     5f                      // yes, we got nothing

        cmp     w0, w2                  // == delimiter?
        beq     6f                      // yes, we're done

        cmp	x0, #'\\'		// == \?
	beq	4f			// skip comment

        // store character, increment pointer
        strb    w0, [x5], #1
        b       1b

4:      // consume til the next newline
        ldrb    w0, [x4], #1

        // if input exhausted while in a comment, there's no word
        cmp     x4, x6
        bgt     5f

	cmp	w0, #'\n'		// eol?
	bne	4b			// no, keep looking
	b	1b

5:      ldr     x5, =word_buffer        // this will make the length 0 later

6:      // update >in and return
        ldr     x0, =var_inbuf          // get start of whole source buffer
        ldr     x0, [x0]
        sub     x1, x4, x0              // >in = curr addr - inbuf
        ldr     x0, =var_to_in
        str     x1, [x0]

        ldr     x0, =word_buffer        // start of parsed string
        sub     x1, x5, x0              // length of parsed string

        POPPSP  lr
        POPPSP  x4
        POPPSP  x5
        POPPSP  x6
        ret

/*

        When the input source is the user input device, attempt to receive input into the terminal
        input buffer. If successful, make the result the input buffer, set >IN to zero, and return
        true. Receipt of a line containing no characters is considered successful. If there is no
        input available from the current input source, return false.

TODO:  check the current source-id before reading from the terminal.
*/

        defcode "refill",6,,refill,parse
        mov     x0, #'>'
        bl      _con_out
        mov     x0, #' '
        bl      _con_out
        bl      _refill
        PUSHPSP x0
        next
_refill:
	// WORD () (address: x0, length: x1)
        PUSHPSP x7
        PUSHPSP x4
        PUSHPSP lr

        // x7 = echo?
        ldr     x7, =var_echo
        ldr     x7, [x7]

        ldr     x4, =buffer
1:	bl	_con_in

        // special cases

        // no input
        cmp     x0, #0
        beq     2f                      // exit (zero in x0 indicates "false")

        // EOL
        cmp     x0, #'\r'               // EOL
        beq     _refill_nl              // exit (non-zero x0 indicates "true")

        // BS
        cmp     x0, #8
        beq     _refill_bs

        // DEL
        cmp     x0, #0x7f
        beq     _refill_bs

        cmp     x7, #0                  // echo == 0?
        beq     2f                      // yes, skip it
        bl      _con_out                // no, echo.
2:      strb    w0, [x4], #1            // store character, increment pointer
        b       1b                      // keep reading characters

_refill_nl:
        ldr     x1, =buffer
        sub     x1, x4, x1              // how many characters did we read?
        ldr     x4, =var_srclen         // address of variable
        str     x1, [x4]                // store number of chars available
        ldr     x4, =var_to_in          // address of variable
        str     xzr, [x4]               // store zero in >in
        cmp     x7, #0                  // echo == 0?
        beq     3f                      // yes, skip it
        bl      _con_out                // no, echo the \r
        mov     w0, #'\n'               // we also need to emit a \n
        bl      _con_out
3:      POPPSP  lr
        POPPSP  x4
        POPPSP  x7
        ret

_refill_bs:
        ldr     x0, =buffer             // start of buffer
        sub     x1, x4, 1
        cmp     x1, x0                  // compare ptr-1 to start
        blt     1b                      // no input so far, do nothing

        cmp     x7, #0                  // echo == 0?
        beq     4f                      // yes, skip it
        mov     w0, #8
        bl      _con_out                // echo the backspace
        mov     w0, #' '                // overwrite the previous character
        bl      _con_out
        mov     w0, #8                  // reposition the cursor
        bl      _con_out
4:      subs    x4, x4, 1               // drop the last character
        b       1b                      // keep looking


        defcode "source",6,,source,refill
        ldr     x1, =buffer
        PUSHPSP x1
        ldr     x1, =var_srclen
        ldr     x0, [x1]
        PUSHPSP x0
        next

/*
	As well as reading in words we'll need to read in numbers and for that we are using a function
	called NUMBER.  This parses a numeric string such as one returned by WORD and pushes the
	number on the parameter stack.

	The function uses the variable BASE as the base (radix) for conversion, so for example if
	BASE is 2 then we expect a binary number.  Normally BASE is 10.

	If the word starts with a '-' character then the returned value is negative.

	If the string can't be parsed as a number (or contains characters outside the current BASE)
	then we need to return an error indication.  So NUMBER actually returns two items on the stack.
	At the top of stack we return the number of unconverted characters (ie. if 0 then all characters
	were converted, so there is no error).  Second from top of stack is the parsed number or a
	partial value if there was an error.
*/

	defcode "number",6,,number,source
	POPPSP	x1		// length of string
	POPPSP	x0		// address of string
	bl	_number
	PUSHPSP	x0		// number
	PUSHPSP	x1		// # unparsed
	next
_number:
	// NUMBER(address: x0, length: x1) (number: x0, unparsed: x1)
        PUSHPSP x4
        PUSHPSP x5
        PUSHPSP x6
        PUSHPSP x7
        PUSHPSP lr

	mov	x2, x0		// address
	mov	x0, #0		// number
	cmp	x1, #0		// length <= 0?
	ble	5f		// really an error, but returns 0 anyway

	ldr	x4, =var_base
	ldr	x4, [x4]	// get BASE
	ldrb	w5, [x2], #1	// get character and increment address
	mov	x7, #0		// set negative flag false
	cmp	x5, #'-'	// leading '-'?
	bne	2f		// nope, try to parse as digit

	mov	x7, #1		// set negative flag true
	subs	x1, x1, #1	// decrement length
	bpl	1f		// >0 so keep going

	mov	x1, #1		// just a sign, no digits, signal an error
	b	5f		// error!
1:
	mul	x6, x0, x4	// number = number * BASE
	mov	x0, x6		// (need to use another register for mul to avoid warning)
	ldrb	w5, [x2], #1	// get character and increment address
2:
	subs	x5, x5, #'0'	// try lower digit bound
	bmi	4f		// nope, < '0' so we're done
	cmp	x5, #10		// try upper digit bound
	blt	3f		// yes, we got one!
	subs	x5, x5, #49	// try lower char bound (49 is 'a'-'0')
	bmi	4f		// nope, < 'a' so we're done
	add	x5, x5, #10	// adjust for first 10 digit values before 'a'
3:
	cmp	x5, x4		// >= BASE?
	bge	4f		// yep, we're done

	// finally, add new digit to number and loop
	add	x0, x0, x5
	subs	x1, x1, #1
	bne	1b
4:
	cmp	x7, #1		// check negative flag
        cneg    x0, x0, eq      // If equal, negate x0
5:
        POPPSP  lr
        POPPSP  x7
        POPPSP  x6
        POPPSP  x5
        POPPSP  x4
	ret

/*
	DICTIONARY LOOK UPS ----------------------------------------------------------------------

	We're building up to our prelude on how FORTH code is compiled, but first we need yet more infrastructure.

	The FORTH word FIND takes a string (a word as parsed by WORD -- see above) and looks it up in the
	dictionary.  What it actually returns is the address of the dictionary header, if it finds it,
	or 0 if it didn't.

	So if DOUBLE is defined in the dictionary, then WORD DOUBLE FIND returns the following pointer:

    pointer to this
	|
	|
	V
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+

	See also >CFA and >dfa.

	FIND doesn't find dictionary entries which are flagged as HIDDEN.  See below for why.
*/

	defcode "find",4,,find,number
	POPPSP	x1			// length of string
	POPPSP	x0			// address of string
	bl	_find
	PUSHPSP	x0			// address of dictionary entry (or 0)
	next
_find:
	// FIND (address: x0, length: x1) (address: x0)
        PUSHPSP x4
        PUSHPSP x5
        PUSHPSP x6
        PUSHPSP x7
        PUSHPSP lr

	mov	x2, x1			// length
	mov	x1, x0			// address
	ldr	x0, =var_latest
	ldr	x0, [x0]		// current dictionary pointer
1:
	cmp	x0, #0			// NULL?
	beq	4f			// end of list!

	ldrb	w3, [x0, #8]		// flags
	and	x3, x3, #(f_hidden)
	cbnz	x3, 2f 			// branch if hidden non zero
	ldrb	w3, [x0, #9]		// len of word we're checking
        cmp     x3, x2                  // check if lengths are equal
        bne     2f                      // if not don't bother looking at the chars

	// we know that x2 = x3, but x3 can be destroyed in the loop
	mov	x4, x1			// x4 <- first letter of input word
	mov	x5, x0                  // addr of word we're checking
	add	x5, x5, #10		// x5 <- first letter of word we're checking
10:
	ldrb 	w6, [x4], #1		// get char A, increment ptr
	ldrb	w7, [x5], #1		// get char B, increment ptr
	cmp	x6, x7			// A = B?
	bne	2f			// nope
	subs	x3, x3, #1		// decrement
	bne	10b			// len > 0, keep going

	// strings are equal, x0 is the correct entry pointer
	b	4f

2:      // names don't match, try the previous word in the dictionary
	ldr	x0, [x0]		// previous dictionary pointer
	b	1b			// try again
4:
        POPPSP  lr
        POPPSP  x7
        POPPSP  x6
        POPPSP  x5
        POPPSP  x4
	ret

/*
	FIND returns the dictionary pointer, but when compiling we need the codeword pointer (recall
	that FORTH definitions are compiled into lists of codeword pointers).  The standard FORTH
	word >CFA turns a dictionary pointer into a codeword pointer.

	The example below shows the result of:

		WORD DOUBLE FIND >CFA

	FIND returns a pointer to this
	|				>CFA converts it to a pointer to this
	|					        |
	V		  			        V
	+-------+-------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK  | FLAGS | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+-------+-------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
						         codeword

	Notes:

	Because names vary in length, this isn't just a simple increment.

	In this FORTH you cannot easily turn a codeword pointer back into a dictionary entry pointer, but
	that is not true in most FORTH implementations where they store a back pointer in the definition
	(with an obvious memory/complexity cost).  The reason they do this is that it is useful to be
	able to go backwards (codeword -> dictionary entry) in order to decompile FORTH definitions
	quickly.

	What does CFA stand for?  My best guess is "Code Field Address".
*/

	defcode ">cfa",4,,tcfa,find
	POPPSP	x0
	bl	_tcfa
	PUSHPSP	x0
	next
_tcfa:
	// TCFA (address: x0) (address: x0)
	add	x0, x0, #8+2+30		// header length is 40 bytes.
	ret

/*
	Related to >CFA is >dfa which takes a dictionary entry address as returned by FIND and
	returns a pointer to the first data field.

	FIND returns a pointer to this
	|				>CFA converts it to a pointer to this
	|					   |
	|					   |	>dfa converts it to a pointer to this
	|					   |		 |
	V					   V		 V
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
						   codeword

	(Note to those following the source of FIG-FORTH / ciforth: My >dfa definition is
	different from theirs, because they have an extra indirection).

	You can see that >dfa is easily defined in FORTH just by adding 4 to the result of >CFA.
*/

	defword ">dfa",4,,tdfa,tcfa
	.quad tcfa		// >CFA		(get code field address)
	.quad incr4		// 4+		(add 8 to it to get to next word)
        .quad incr4		// 4+
	.quad exit		// EXIT		(return from FORTH word)

/*
	COMPILING ----------------------------------------------------------------------

	Now we'll talk about how FORTH compiles words.  Recall that a word definition looks like this:

		: DOUBLE DUP + ;

	and we have to turn this into:

	  pointer to previous word
	   ^
	   |
	+--|------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+--|---------+------------+------------+
           ^       len                         pad  codeword      |
	   |							  V
	  LATEST points here				points to codeword of DUP

	There are several problems to solve.  Where to put the new word?  How do we read words?  How
	do we define the words : (COLON) and ; (SEMICOLON)?

	FORTH solves this rather elegantly and as you might expect in a very low-level way which
	allows you to change how the compiler works on your own code.

	FORTH has an INTERPRET function (a true interpreter this time, not DOCOL) which runs in a
	loop, reading words (using WORD), looking them up (using FIND), turning them into codeword
	pointers (using >CFA) and deciding what to do with them.

	What it does depends on the mode of the interpreter (in variable STATE).

	When STATE is zero, the interpreter just runs each word as it looks them up.  This is known as
	immediate mode.

	The interesting stuff happens when STATE is non-zero -- compiling mode.  In this mode the
	interpreter appends the codeword pointer to user memory (the HERE variable points to the next
	free byte of user memory -- see DATA SEGMENT section below).

	So you may be able to see how we could define : (COLON).  The general plan is:

	(1) Use WORD to read the name of the function being defined.

	(2) Construct the dictionary entry -- just the header part -- in user memory:

    pointer to previous word (from LATEST)			+-- Afterwards, HERE points here, where
	   ^							|   the interpreter will start appending
	   |							V   codewords.
	+--|------+---+---+---+---+---+---+---+---+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      |
	+---------+---+---+---+---+---+---+---+---+------------+
                   len                         pad  codeword

	(3) Set LATEST to point to the newly defined word, ...

	(4) .. and most importantly leave HERE pointing just after the new codeword.  This is where
	    the interpreter will append codewords.

	(5) Set STATE to 1.  This goes into compile mode so the interpreter starts appending codewords to
	    our partially-formed header.

	After : has run, our input is here:

	: DOUBLE DUP + ;
	         ^
		 |
		Next byte returned by KEY will be the 'D' character of DUP

	so the interpreter (now it's in compile mode, so I guess it's really the compiler) reads "DUP",
	looks it up in the dictionary, gets its codeword pointer, and appends it:

									     +-- HERE updated to point here.
									     |
									     V
	+---------+---+---+---+---+---+---+---+---+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        |
	+---------+---+---+---+---+---+---+---+---+------------+------------+
                   len                         pad  codeword

	Next we read +, get the codeword pointer, and append it:

											  +-- HERE updated to point here.
											  |
											  V
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          |
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+
                   len                         pad  codeword

	The issue is what happens next.  Obviously what we _don't_ want to happen is that we
	read ";" and compile it and go on compiling everything afterwards.

	At this point, FORTH uses a trick.  Remember the length byte in the dictionary definition
	isn't just a plain length byte, but can also contain flags.  One flag is called the
	IMMEDIATE flag (F_IMMED in this code).  If a word in the dictionary is flagged as
	IMMEDIATE then the interpreter runs it immediately _even if it's in compile mode_.

	This is how the word ; (SEMICOLON) works -- as a word flagged in the dictionary as IMMEDIATE.

	And all it does is append the codeword for EXIT on to the current definition and switch
	back to immediate mode (set STATE back to 0).  Shortly we'll see the actual definition
	of ; and we'll see that it's really a very simple definition, declared IMMEDIATE.

	After the interpreter reads ; and executes it 'immediately', we get this:

	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
                   len                         pad  codeword					       ^
												       |
												      HERE
	STATE is set to 0.

	And that's it, job done, our new definition is compiled, and we're back in immediate mode
	just reading and executing words, perhaps including a call to test our new word DOUBLE.

	The only last wrinkle in this is that while our word was being compiled, it was in a
	half-finished state.  We certainly wouldn't want DOUBLE to be called somehow during
	this time.  There are several ways to stop this from happening, but in FORTH what we
	do is flag the word with the HIDDEN flag (F_HIDDEN in this code) just while it is
	being compiled.  This prevents FIND from finding it, and thus in theory stops any
	chance of it being called.

	The above explains how compiling, : (COLON) and ; (SEMICOLON) works and in a moment I'm
	going to define them.  The : (COLON) function can be made a little bit more general by writing
	it in two parts.  The first part, called CREATE, makes just the header:

						   +-- Afterwards, HERE points here.
						   |
						   V
	+---------+---+---+---+---+---+---+---+---+
	| LINK    | 6 | D | O | U | B | L | E | 0 |
	+---------+---+---+---+---+---+---+---+---+
                   len                         pad

	and the second part, the actual definition of : (COLON), calls CREATE and appends the
	DOCOL codeword, so leaving:

								+-- Afterwards, HERE points here.
								|
								V
	+---------+---+---+---+---+---+---+---+---+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      |
	+---------+---+---+---+---+---+---+---+---+------------+
                   len                         pad  codeword

	CREATE is a standard FORTH word and the advantage of this split is that we can reuse it to
	create other types of words (not just ones which contain code, but words which contain variables,
	constants and other data).
*/

	defcode "create",6,,create,tdfa // ( addr len -- )
	POPPSP	x1                      // name length
	POPPSP	x0                      // name address

	ldr	x2, =var_here           // address of HERE
	ldr	x3, [x2]                // x3 <- value of HERE, address of new header
	ldr	x4, =var_latest         // address of LATEST
	ldr	x5, [x4]                // x5 <- value of LATEST, link pointer
	str	x3, [x4]                // update LATEST to refer to new header
	str	x5, [x3], #8            // store link pointer in header, increment header

	strb	wzr, [x3], #1	        // store flag byte, increment header
	strb	w1, [x3], #1	        // store name length byte, increment header

	mov	x16, #30
	sub	x16, x16, x1

	// Copy the name into the definition.
1:
	cmp	x1, #0
        b.eq    2f
	ldrb	w4, [x0], #1           // get character, increment
	strb	w4, [x3], #1	        // put character, increment header
	subs	x1, x1, #1              // decrement length
	bne	1b

	// Pad out the name to 30 bytes with commas.
2:
	mov	w15, ','
3:
	cmp	x16, #0
        b.eq    4f
	strb	w15, [x3], #1	        // put character, increment header
	subs	x16, x16, #1            // decrement length
	bne	3b

4:
	add	x3, x3, #7              // align to 8 byte boundary
	and	x3, x3, #~7

	str	x3, [x2]                // update HERE
	next

/*
	Because I want to define : (COLON) in FORTH, not assembler, we need a few more FORTH words
	to use.

	The first is , (COMMA) which is a standard FORTH word which appends a 32 bit integer to the user
	memory pointed to by HERE, and adds 4 to HERE.  So the action of , (COMMA) is:

							previous value of HERE
								 |
								 V
	+---------+---+---+---+---+---+---+---+---+-- - - - - --+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 |             |  <data>    |
	+---------+---+---+---+---+---+---+---+---+-- - - - - --+------------+
                   len                         pad		              ^
									      |
									new value of HERE

	and <data> is whatever 32 bit integer was at the top of the stack.

	, (COMMA) is quite a fundamental operation when compiling.  It is used to append codewords
	to the current word that is being compiled.
*/

	defcode ",",1,,comma,create
	POPPSP	x0                      // Code pointer to store.
	bl	_comma
	next
_comma:
	// COMMA (codeword: x0) ()
	ldr	x1, =var_here           // address of HERE
	ldr	x2, [x1]                // value of HERE
	str	x0, [x2], #8            // store it and increment x2
	str	x2, [x1]	        // update HERE
	ret

/*
	Our definitions of : (COLON) and ; (SEMICOLON) will need to switch to and from compile mode.

	Immediate mode vs. compile mode is stored in the global variable STATE, and by updating this
	variable we can switch between the two modes.

	For various reasons which may become apparent later, FORTH defines two standard words called
	[ and ] (LBRAC and RBRAC) which switch between modes:

	Word	Assembler	Action		Effect
	[	LBRAC		STATE := 0	Switch to immediate mode.
	]	RBRAC		STATE := 1	Switch to compile mode.

	[ (LBRAC) is an IMMEDIATE word.  The reason is as follows: If we are in compile mode and the
	interpreter saw [ then it would compile it rather than running it.  We would never be able to
	switch back to immediate mode!  So we flag the word as IMMEDIATE so that even in compile mode
	the word runs immediately, switching us back to immediate mode.
*/

	defcode "[",1,f_immed,lbrac,comma
	ldr	x0, =var_state          // address of STATE
	str	xzr, [x0]               // store 0 in STATE
	next

	defcode "]",1,,rbrac,lbrac
	ldr	x0, =var_state          // address of STATE
	mov	x1, #1                  // put a 1 in the register
	str	x1, [x0]                // store 1 in STATE
	next

/*

	Now we can define : (COLON) using CREATE.  It just calls CREATE, appends DOCOL (the codeword), sets
	the word HIDDEN and goes into compile mode.

*/

	defword ":",1,,colon,rbrac
	.quad word                      // Get the name of the new word
	.quad create                    // CREATE the dictionary entry / header
	.quad lit, docol, comma         // Append DOCOL  (the codeword).
	.quad latest, fetch, hidden     // Make the word hidden (see below for definition).
	.quad rbrac                     // Go into compile mode.
	.quad exit                      // Return from the function.

/*
	; (SEMICOLON) is also elegantly simple.  Notice the F_IMMED flag.
*/

	defword ";",1,f_immed,semicolon,colon
	.quad lit, exit, comma          // Append EXIT (so the word will return).
	.quad latest, fetch, hidden     // Toggle hidden flag -- unhide the word (see below for definition).
	.quad lbrac                     // Go back to IMMEDIATE mode.
	.quad exit                      // Return from the function.

/*
	EXTENDING THE COMPILER ----------------------------------------------------------------------

	Words flagged with IMMEDIATE (F_IMMED) aren't just for the FORTH compiler to use.  You can define
	your own IMMEDIATE words too, and this is a crucial aspect when extending basic FORTH, because
	it allows you in effect to extend the compiler itself.  Does gcc let you do that?

	Standard FORTH words like IF, WHILE, ." and so on are all written as extensions to the basic
	compiler, and are all IMMEDIATE words.

	The IMMEDIATE word toggles the F_IMMED (IMMEDIATE flag) on the most recently defined word,
	or on the current word if you call it in the middle of a definition.

	Typical usage is:

	: MYIMMEDWORD IMMEDIATE
		...definition...
	;

	but some FORTH programmers write this instead:

	: MYIMMEDWORD
		...definition...
	; IMMEDIATE

	The two usages are equivalent, to a first approximation.
*/

	defcode "immediate",9,f_immed,immediate,semicolon
	ldr	x0, =var_latest		// address of LATEST
	ldr	x0, [x0]		// value of LATEST
	ldrb	w1, [x0, #8]		// get flag byte
	eor	x1, x1, #f_immed	// toggle IMMED bit
	strb	w1, [x0, #8]		// update flag byte
	next

/*
	'addr HIDDEN' toggles the hidden flag (F_HIDDEN) of the word defined at addr.  To hide the
	most recently defined word (used above in : and ; definitions) you would do:

		LATEST @ HIDDEN

	'hide word' toggles the flag on a named 'word'.

	Setting this flag stops the word from being found by FIND, and so can be used to make 'private'
	words.  For example, to break up a large word into smaller parts you might do:

		: SUB1 ... subword ... ;
		: SUB2 ... subword ... ;
		: SUB3 ... subword ... ;
		: MAIN ... defined in terms of SUB1, SUB2, SUB3 ... ;
		hide SUB1
		hide SUB2
		hide SUB3

	After this, only MAIN is 'exported' or seen by the rest of the program.
*/

	defcode "hidden",6,,hidden,immediate
	POPPSP	x0			// dictionary entry
	ldrb	w1, [x0, #8]		// get flag byte
	eor	x1, x1, #f_hidden	// toggle HIDDEN bit
	strb	w1, [x0, #8]		// update flag byte
	next

        defword "hide",4,,hide,hidden
	.quad word		// Get the word (after HIDE).
	.quad find		// Look up in the dictionary.
	.quad hidden		// Set F_HIDDEN flag.
	.quad exit		// Retu

/*
	' (TICK) is a standard FORTH word which returns the codeword pointer of the next word.

	The common usage is:

	' FOO ,

	which appends the codeword of FOO to the current word we are defining (this only works in compiled code).

	You tend to use ' in IMMEDIATE words.  For example an alternate (and rather useless) way to define
	a literal 2 might be:

	: LIx2 IMMEDIATE
		' LIT ,		\ Appends LIT to the currently-being-defined word
		2 ,		\ Appends the number 2 to the currently-being-defined word
	;

	So you could do:

	: double LIx2 * ;

	(If you don't understand how LIx2 works, then you should review the material about compiling words
	and immediate mode).

	This definition of ' uses a cheat which I copied from buzzard92.  As a result it only works in
	compiled code.  It is possible to write a version of ' based on WORD, FIND, >CFA which works in
	immediate mode too.
*/

	defcode "'",1,,tick,hide
	ldr	x0, [NIP], #8   	// load address of next word from NIP, increment NIP to skip it
	PUSHPSP	x0
	next

/*
	BRANCHING ----------------------------------------------------------------------

	It turns out that all you need in order to define looping constructs, IF-statements, etc.
	are two primitives.

	BRANCH is an unconditional branch. 0BRANCH is a conditional branch (it only branches if the
	top of stack is zero).

	The diagram below shows how BRANCH works in some imaginary compiled word.  When BRANCH executes,
	%esi starts by pointing to the offset field (compare to LIT above):

	+---------------------+-------+---- - - ---+------------+------------+---- - - - ----+------------+
	| (Dictionary header) | DOCOL |            | BRANCH     | offset     | (skipped)     | word       |
	+---------------------+-------+---- - - ---+------------+-----|------+---- - - - ----+------------+
								   ^  |			      ^
								   |  |			      |
								   |  +-----------------------+
								  %esi added to offset

	The offset is added to %esi to make the new %esi, and the result is that when next runs, execution
	continues at the branch target.  Negative offsets work as expected.

	0BRANCH is the same except the branch happens conditionally.

	Now standard FORTH words such as IF, THEN, ELSE, WHILE, REPEAT, etc. can be implemented entirely
	in FORTH.  They are IMMEDIATE words which append various combinations of BRANCH or 0BRANCH
	into the word currently being compiled.

	As an example, code written like this:

		condition-code IF true-part THEN rest-code

	compiles to:

		condition-code 0BRANCH OFFSET true-part rest-code
					  |		^
					  |		|
					  +-------------+
*/

	defcode "branch",6,,branch,tick
	ldr	x0, [NIP]	// offset to add
	add	NIP, NIP, x0	// add it!
	next

	defcode "0branch",7,,zbranch,branch
	POPPSP	x0
	cmp	x0, #0		// top of stack zero?
	beq	code_branch	// yes, do the branch
	add	NIP, NIP, #8	// no, skip the offset
	next

/*
	LITERAL STRINGS ----------------------------------------------------------------------

	LITSTRING is a primitive used to implement the ." and S" operators (which are written in
	FORTH).  See the definition of those operators later.

	TELL just prints a string.  It's more efficient to define this in assembly because we
	can make it a single Linux syscall.
*/

	defcode "litstring",9,,litstring,zbranch
	ldr	x0, [NIP], #8	// get length of string, increment
	PUSHPSP	NIP		// push address of string
	PUSHPSP	x0		// push length of string
	add	NIP, NIP, x0	// skip past the string
	add	NIP, NIP, #7	// align
	and	NIP, NIP, #~7
	next

        // ( addr length -- ) writes a string to output
	defcode "tell",4,,tell,litstring
        POPPSP  x2                      // x2 <- len
        POPPSP  x1                      // x1 <- addr
        bl      _tell
	next

        .global _tell
_tell:
        PUSHPSP lr
        cmp     x2, #0
        beq     2f
1:      ldrb    w0, [x1], #1
        bl      _con_out
        subs    x2, x2, #1
        bgt     1b
2:      POPPSP  lr
        ret

/*
	QUIT AND INTERPRET ----------------------------------------------------------------------

	QUIT is the first FORTH function called, almost immediately after the FORTH system "boots".
	As explained before, QUIT doesn't "quit" anything.  It does some initialisation (in
	particular it clears the return stack and restores input) and it calls INTERPRET in a loop
	to interpret commands.  The reason it is called QUIT is because you can call it from your
	own FORTH words in order to "quit" your program and start again at the user prompt.

	INTERPRET is the FORTH interpreter ("toploop", "toplevel" or "REPL" might be a more accurate
	description -- see: http://en.wikipedia.org/wiki/REPL).
*/

        defword "quit",4,,quit,tell
	.quad   rz,rspstore	  // r0 rsp!
        .quad   lit,0,srcid,store // 0 srcid !
        .quad   lit,0,state,store // [
        .quad   in0,fetch         // in0 @
        .quad   inbuf,store       // inbuf !
        .quad   sz,fetch,dspstore // s0 @ dsp!
        .quad   refill            // do refill
        .quad   zbranch,12*8      // exit if refill failed
	.quad   interpret	  // interpret
        .quad   srclen,fetch      // srclen @
        .quad   to_in,fetch       // >in @
        .quad   sub,zgt           // - 0>
        .quad   zbranch,-88       // if-not jump back to refill
        .quad   branch,-96        // repeat
        .quad   exit

/*
	This interpreter is pretty simple, but remember that in FORTH you can always override
	it later with a more powerful one!
 */

	defcode "interpret",9,,interpret,quit
8:      mov	x7, #0			// interpret_is_num = 0
	bl	_word			// returns x0 = address, x1 = length
        cmp     x1, #0                  // is a word available?
        bne     3f                      // yes, go to look it up
        next                            // no, exit
3:
        // look up word
	mov	x4, x0			// save word in x4, x5
	mov	x5, x1

        // is it in the dictionary?
	bl	_find			// returns x0 = dictionary entry
	cmp	x0, #0			// did we find it?
	beq	1f			// no, it might be a number

	// found in dictionary, check if it's immediate
	ldrb	w6, [x0, #8]		// load length/flags byte
	bl	_tcfa			// leaves codeword pointer in x0
	tst	w6, #f_immed		// is it immediate?
	bne	4f			// yes, jump straight to executing
	b	2f			// no, jump to compile/execute

1:	// not in dictionary, check if it's a number
	add	x7, x7, #1		// interpret_is_num = 1
	mov	x0, x4			// address
	mov	x1, x5			// length
	bl	_number			// returns x0 = number, x1 = unparsed
	cmp	x1, #0			// were we able to parse it?
	bne	6f			// not a number and not a word, report error

	mov	x6, x0			// yes, it was a number
	ldr	x0, =lit		// assume we need LIT as the codeword

2:	// are we compiling or executing?
	ldr	x2, =var_state		// address of STATE
	ldr	x2, [x2]		// value of STATE
	cmp	x2, #0			// are we interpreting?
	beq	4f			// yes, jump straight to execute

	// compiling, append word to current dictionary definition
	bl	_comma			// expects codeword in x0 (from earlier)
	cmp	x7, #0			// interpret_is_num == 0?
	beq     8b                      // yep, so we're done

	mov	x0, x6			// number
	bl	_comma			// expects number in x0
	b       8b

4:	// executing, so run the word
	cmp	x7, #0			// interpret_is_num != 0?
	bne	5f			// yep, so let's push

	ldr	x1, [x0]                // not a literal, execute now
        sub     NIP, NIP, #8            // set this up to re-enter interpret when the word exits
	br	x1                      // go execute. this will not return here

5:	// push literal on the stack
	PUSHPSP	x6
        b       8b

6:
        // todo : this should abort instead of print

	// parse error
	ldr	x1, =errmsg		// address
	mov	x2, #errmsgend-errmsg	// length
        bl      _tell                   // display it

        mov     x1, x4                  // address of word
        mov     x2, x5                  // length of word
        bl      _tell

	ldr	x1, =errmsgnl
	mov	x2, #errmsgnlend-errmsgnl
        bl      _tell

        RESET_INPUT
	ldr	NIP, =warm_start        // re-initialize
	next                            // start from the beginning

	.section .rodata
errmsg: .ascii "PARSE ERROR: '"
errmsgend:
errmsgnl: .ascii "'\r\n"
errmsgnlend:

crnl:	.ascii "\r\n"

hmsg: .ascii " (hidden) "
hmsgend:

hellomsg: .ascii "Hello world!\r\n"
hellomsgend:

testmsg: .ascii "Testing!\r\n"
testmsgend:

/*
	ODDS AND ENDS ----------------------------------------------------------------------

	CHAR puts the ASCII code of the first character of the following word on the stack.  For
	example CHAR A puts 65 on the stack.

	EXECUTE is used to run execution tokens.  See the discussion of execution tokens in the
	FORTH code for more details.

	In this FORTH, EXECUTE is the last word in the built-in dictionary so we initialise the
	LATEST variable to point to it. This means that if you want to extend the builtin
	dictionary, you must put new words before EXECUTE, or else change how LATEST is initialised.

*/

        defcode "fence",5,,fence,interpret
        dmb     st                      // memory barrier. this is too pessimistic it will be slow
        next

        // Data cache clean
        // Note: this operates on an entire cache line
        defcode "dcc",3,,dcclean,fence
        POPPSP  x0
        dc      cvac, x0
        next

        // Data cache invalidate
        // Note: this operates on an entire cache line
        defcode "dci",3,,dcinval,dcclean
        POPPSP  x0
        dc      ivac, x0
        next

        // Data cache clean and invalidate
        // Note: this operates on an entire cache line
        defcode "dcci",4,,dccleaninval,dcinval
        POPPSP  x0
        dc      civac, x0
        next

	// Simple test word.
        defcode "hello",5,,hello,dccleaninval
	ldr	x1, =hellomsg		// address
	mov	x2, #hellomsgend-hellomsg	// length
        bl      _tell
	next

	// Word to test the call subroutine instructions.

        defcode "test-call",9,,test_call,hello
	adr     x30,#24 	// 0: Load return address
	adr	x17,#12		// 4: Load addr of f address
	ldr	x17,[x17]     	// 8: Load f address
	br	x17          	// 12:Branch to f
	.ascii	"ADDRESSX"	// 16: address of message f
	mov	x19, #42	// 24: Some place to come back to
	next

_saymsg:
        stp     x30, x1, [sp, #-16]!
	ldr	x1, =testmsg		// address
	mov	x2, #testmsgend-testmsg	// length
        bl      _tell
        ldp     x30, x1, [sp], #16
	ret

	// Example of a secondary in assembly.
        defword "hellohello",10,,hellohello,test_call
	.quad hello
	.quad hello
	.quad exit		// Return

        // ( charcode bgcolor fgcolor pitch addr -- )
        defcode "drawchar",8,,drawchar,hellohello
        POPPSP  x0
        POPPSP  x1
        POPPSP  x2
        POPPSP  x3
        POPPSP  x4
        PUSHPSP lr
        bl      draw_char
        POPPSP  lr
        next

	defcode "char",4,,char,drawchar
	bl	_word			// returns x0 = address, x1 = length
	ldrb	w0, [x0]		// get first character
	PUSHPSP	x0			// push it
	next

	defcode "execute",7,,execute,char
	POPPSP	x0			// grab execution token
	ldr	x1, [x0]	        // load codeword
	br	x1		        // jump to codeword

/*
	DATA SEGMENT ----------------------------------------------------------------------

	Here we set up the data segment, used for user definitions and variously known as just
	the 'data segment', 'user memory' or 'user definitions area'.  It is an area of memory which
	grows upwards and stores both newly-defined FORTH words and global variables of various
	sorts.

	It is completely analogous to the C heap, except there is no generalised 'malloc' and 'free'
	(but as with everything in FORTH, writing such functions would just be a Simple Matter
	Of Programming).  Instead in normal use the data segment just grows upwards as new FORTH
	words are defined/appended to it.

        Without an underlying operating system, we have to get the addresses from _somewhere_. In
        this forth, we will require that the kernel binary supplies these addresses in the form of
        linker symbols.

        The parameter stack grows downward from _forth_pstack_high toward _forth_pstack_low.

        Similarly, the return stack grows downward from _forth_rstack_high toward _forth_rstack_low.

        At this time, we make absolutely no attempt to protect memory. Stack overflow is a real
        possibility.

*/

	.section .rodata
        .align 3

/*
	We allocate static space for the various stacks and buffers.
*/
        .macro defstack lbl,size
        .align 12
        \lbl: .space \size
        \lbl\()_top:
        .endm

	.bss
        defstack return_stack,8*1024       // 8K
        defstack data_stack,8*1024         // 8K
        defstack input_stack,8*64          // 128B (allows 8 nested input sources)

        .align 12
buffer: .space 4096                        // 4K (temporary input buffer)

        .align 12
data_segment:
        // data segment starts here and takes the rest of the memory space.
