\ -*- forth -*-
\ 
\ This is the second stage of AApen boot code, which finishes up the boot sequnce.
\
\
\ Based on jonesforth.f. Original license:
\
\	A sometimes minimal FORTH compiler and tutorial for Linux / i386 systems.
\	By Richard W.M. Jones <rich@annexia.org> http://annexia.org/forth
\	This is PUBLIC DOMAIN (see public domain release statement below).
\	$Id: jonesforth.f,v 1.18 2009-09-11 08:32:33 rich Exp $
\
\	The first part of this tutorial is in jonesforth.S.  Get if from http://annexia.org/forth
\
\	PUBLIC DOMAIN ----------------------------------------------------------------------
\
\	I, the copyright holder of this work, hereby release it into the public domain. This applies worldwide.
\
\	In case this is not legally possible, I grant any entity the right to use this work for any purpose,
\	without any conditions, unless such conditions are required by law.
\


( Standard FORTH defines a concept called an 'execution token' -- or 'xt' -- which is very
  similar to a function pointer in C.  We map the execution token to a codeword address.

		execution token of DOUBLE is the address of this codeword
						    |
						    V
+---------+---+---+---+---+---+---+---+---+-------+------------+------------+------------+------------+
| LINK    | 0 | 6 | D | O | U | B | L | E | , ... | DOCOL      | DUP        | +          | EXIT       |
+---------+---+---+---+---+---+---+---+---+-------+------------+------------+------------+------------+
                   flg len                         pad      codeword

  There is one assembler primitive for execution tokens, EXECUTE, which runs them.

  You can make an execution token for an existing word the long way using >CFA,
  ie: WORD [foo] FIND >CFA will push the xt for foo onto the stack where foo is the
  next word in input.  So a very slow way to run DOUBLE might be:

		: double dup + ;
		: slow word find >cfa execute ;
		5 slow double . cr	\ prints 10

  We also offer a simpler and faster way to get the execution token of any word FOO:
  
  	['] FOO

  More useful is to define anonymous words and/or to assign xt's to variables.

  To define an anonymous word -- and push its xt on the stack -- use :NONAME ... ; as in this
  example:

		:noname ." anon word was called" cr ;	\ pushes xt on the stack
		dup execute execute			\ executes the anon word twice

  Stack parameters work as expected:

		:noname ." called with parameter " . cr ;
		dup
		10 swap execute		\ prints 'called with parameter 10'
		20 swap execute		\ prints 'called with parameter 20'

  Notice that the above code has a memory leak: the anonymous word is still compiled
  into the data segment, so even if you lose track of the xt, the word continues to
  occupy memory.  A good way to keep track of the xt and thus avoid the memory leak is
  to assign it to a CONSTANT, VARIABLE or VALUE:

		0 value anon
		:noname ." anon word was called" cr ; to anon
		anon execute
		anon execute

  Another use of :NONAME is to create an array of functions which can be called quickly
  -- think: fast switch statement.  This example is adapted from the ANS FORTH standard:

		10 cells allot constant cmd-table
		: set-cmd cells cmd-table + ! ;
		: call-cmd cells cmd-table + @ execute ;

		:noname ." alternate 0 was called" cr ;	 0 set-cmd
		:noname ." alternate 1 was called" cr ;	 1 set-cmd
			\ etc...
		:noname ." alternate 9 was called" cr ;	 9 set-cmd

		0 call-cmd
		1 call-cmd
)

: :noname
	0 0 header	( create a word with no name - we need a dictionary header because ; expects it )
	here @		( current here value is the address of the codeword, ie. the xt )
	docol ,		( compile docol -- the codeword )
	]		( go into compile mode )
;

: ['] immediate
	' lit ,		( compile lit )
;

( Print a stack trace by walking up the return stack. )

: print-stack-trace
	rsp@				( start at caller of this function )
	begin
		dup r0 8- <		( rsp < r0 )
	while
		dup @			( get the return stack entry )
		case
		' exception-marker 8+ of	( is it the exception stack frame? )
			." catch ( dsp="
			8+ dup @ u.		( print saved stack pointer )
			." ) "
		endof
						( default case )
			dup
			cfa>			( look up the codeword to get the dictionary entry )
			?dup if			( and print it )
				2dup			( dea addr dea )
				id.			( print word from dictionary entry )
				[ char + ] literal emit
				swap >dfa 8+ - .	( print offset )
			then
		endcase
		8+			( move up the stack )
	repeat
	drop
	cr
;

( C-Strings: FORTH strings are represented by a start address and length kept on the stack or in memory.

  Most FORTHs don't handle C strings, but we need them in order to access the process arguments
  and environment left on the stack by the Linux kernel, and to make some system calls.

  Operation	Input		Output		FORTH word	Notes
  ----------------------------------------------------------------------

  Create FORTH string		addr len	S" ..."

  Create C string		c-addr		Z" ..."

  C -> FORTH	c-addr		addr len	dup strlen

  FORTH -> C	addr len	c-addr		cstring		Allocated in a temporary buffer, so
  								should be consumed / copied immediately.
  								FORTH string should not contain NULs.

  For example, DUP STRLEN TELL prints a C string.
)

( z" .." is like z" ..." except that the string is terminated by an ASCII NUL character.

  to make it more like a C string, at runtime z" just leaves the address of the string
  on the stack -- not address & length as with s".  To implement this we need to add the
  extra NUL to the string and also a drop instruction afterwards.  Apart from that the
  implementation just a modified s".
)

: z" immediate
	state @ if	( compiling? )
		' litstring ,	( compile litstring )
		here @		( save the address of the length word on the stack )
		0 ,		( dummy length - we don't know what it is yet )
                '"' parse s,
		0 here @ c!	( add the ascii nul byte )
		1 here +!
		drop		( drop the double quote character at the end )
		dup		( get the saved address of the length word )
		here @ swap -	( calculate the length )
		8-		( subtract 4 -- because we measured from the start of the length word )
		swap !		( and back-fill the length location )
		align		( round up to next multiple of 4 bytes for the remaining code )
		' drop ,	( compile drop -- to drop the length )
	else		( immediate mode )
	        here @		( get the start address of the temporary space )
                '"' parse s,
		0 here @ c!	( store final ascii nul )
		here @		( push the start address )
	then
;

: strlen 	( str -- len )
	dup		( save start address )
	begin
		dup c@ 0<>	( zero byte found? )
	while
		1+
	repeat

	swap -		( calculate the length )
;

: cstring	( addr len -- c-addr )
	swap over	( len saddr len )
	here @ swap	( len saddr daddr len )
	cmove		( len )

	here @ +	( daddr+len )
	0 swap c!	( store terminating nul char )

	here @ 		( push start address )
;

: memset        ( len byte addr -- addr+len )
        rot                     ( byte addr len )
        begin
                dup 0>
        while
                -rot            ( len byte addr )
                2dup            ( len byte addr byte addr )
                c!              ( len byte addr )
                1+ rot 1-       ( byte addr+1 len-1 )
        repeat
        rot 2drop
;

( xray-p Dump out the details of a word from its address )
: xray-p ( waddr -- )
  dup ." Word address: " .x cr
  dup ." Link address: "  @ .x cr
  dup ." Flags: " 8 + c@ .x cr
  dup ." Name len: " 9 + c@ .x cr
        dup ." Name: " 10 + 30 dump 
  dup ." Code Word: " 40 + @ .x cr
  ." Next 128 bytes: " 48 + 128 dump
;


( read the name of a word and dump its details )
: xray ( -- )
  word find ?dup 0= if
    ." not found" cr exit
  else
    xray-p
  then
;

( Another concern that didn't exist when FORTH was created was caching. In our multicore and
  memory-mapped world, we have to do some manual cache maintenance when handing memory off
  between cores or devices. That means we need to be able to clean regions of the cache by
  writing modified contents to main memory or invalidate regions.

  --- this comment is a placeholder for when we figure out what these words should be ---
)

( /string is used to remove or add characters relative to the current position in the
  character string. Positive values of n will exclude characters from the string while
  negative values of n will include charactesr to the left of the string.)

: /string ( c-addr_1 u_1 n -- c-addr_2 u_2 ) tuck - >r chars + r> ;

( If u is greater than zero, store char in each of u consecutive characters of memory
  beginning at c-addr.)

: fill ( c-addr u char -- ) -rot 0 ?do 2dup c! 1+ loop 2drop ;

( if u is greater than zero, store the character value for space in u consecutive character
  positions beginning at c-addr. )

: blank ( c-addr u -- ) bl fill ;

( copy n words from addr to , )

: ,* ( addr n - )
  begin
    dup 0>
  while
    swap dup w@ w, 4+ swap 1-
  repeat
  2drop
;

( align HERE to 16 byte boundary )

here @ 15 + 15 invert and here !
1024 cells allot constant scratch

: unused lastcell here @ - 8 / ;

( BIOS INTERFACE )
0
1 cells +field -.xres
1 cells +field -.yres
1 cells +field -.addr
1 cells +field -.size
1 cells +field -.pitch
1 cells +field -.bgcolor
1 cells +field -.fgcolor
1 cells +field -.cursorx
1 cells +field -.cursory
constant fb%

fb -.xres @  8 / constant screen-cols
fb -.yres @ 16 / constant screen-rows

00 value black
01 value white
02 value red
03 value cyan
04 value violet
05 value green
06 value blue
07 value yellow
08 value orange
09 value brown
10 value light-red
11 value dark-grey
12 value grey
13 value light-green
14 value light-blue
15 value light-grey

: clr@ fb -.bgcolor @ fb -.fgcolor @ ;
: clr! fb -.fgcolor ! fb -.bgcolor ! ;

blue light-blue clr!

: csr@ fb -.cursorx @ fb -.cursory @ ;
: csr! fb -.cursory ! fb -.cursorx ! ;

: next-line
  csr@
  nip 0 swap
  1+
  dup screen-rows >= if
    drop 0
  then
  csr!
;

: next-char
  csr@
  swap 1+
  dup screen-cols >= if
    2drop next-line
  else
    swap csr!
  then
;

: home 0 0 csr! ;
: fg! clr@ drop swap clr! ;
: bg! clr@ nip       clr! ;

: aapen-logo
  home cr cr
  yellow fg!
  s"                 AAA                              AAA                                                                        " tell cr
  s"                A:::A                            A:::A                                                                       " tell cr
  s"               A:::::A                          A:::::A                                                                      " tell cr
  green fg!
  s"              A:::::::A                        A:::::::A                                                                     " tell cr
  s"             A:::::::::A                      A:::::::::A          AAAAA   AAAAAAAAA       AAAAAAAAAAAA    AAAA  AAAAAAAA    " tell cr
  s"            A:::::A:::::A                    A:::::A:::::A         A::::AAA:::::::::A    AA::::::::::::AA  A:::AA::::::::AA  " tell cr
  red fg!
  s"           A:::::A A:::::A                  A:::::A A:::::A        A:::::::::::::::::A  A::::::AAAAA:::::AAA::::::::::::::AA " tell cr
  s"          A:::::A   A:::::A                A:::::A   A:::::A       AA::::::AAAAA::::::AA::::::A     A:::::AAA:::::::::::::::A" tell cr
  yellow fg!
  s"         A:::::A     A:::::A              A:::::A     A:::::A       A:::::A     A:::::AA:::::::AAAAA::::::A  A:::::AAAA:::::A" tell cr
  s"        A:::::AAAAAAAAA:::::A            A:::::AAAAAAAAA:::::A      A:::::A     A:::::AA:::::::::::::::::A   A::::A    A::::A" tell cr
  s"       A:::::::::::::::::::::A          A:::::::::::::::::::::A     A:::::A     A:::::AA::::::AAAAAAAAAAA    A::::A    A::::A" tell cr
  green fg!
  s"      A:::::AAAAAAAAAAAAA:::::A        A:::::AAAAAAAAAAAAA:::::A    A:::::A    A::::::AA:::::::A             A::::A    A::::A" tell cr
  s"     A:::::A             A:::::A      A:::::A             A:::::A   A:::::AAAAA:::::::AA::::::::A            A::::A    A::::A" tell cr
  red fg!
  s"    A:::::A               A:::::A    A:::::A               A:::::A  A::::::::::::::::A  A::::::::AAAAAAAA    A::::A    A::::A" tell cr
  s"   A:::::A                 A:::::A  A:::::A                 A:::::A A::::::::::::::AA    AA:::::::::::::A    A::::A    A::::A" tell cr
  s"  AAAAAAA                   AAAAAAAAAAAAAA                   AAAAAAAA::::::AAAAAAAA        AAAAAAAAAAAAAA    AAAAAA    AAAAAA" tell cr
  s"                                                                  A:::::A                                                    " tell cr
  yellow fg!
  s"                                                                  A:::::A                                                    " tell cr
  s"                                                                 A:::::::A                                                   " tell cr
  s"                                                                 A:::::::A                                                   " tell cr
  green fg!
  s"                                                                 A:::::::A                                                   " tell cr
  s"                                                                 AAAAAAAAA                                                   " tell cr
  light-blue fg!
;

: (concls) 'esc' >con 'c' >con ;
: (dispcls) home screen-rows screen-cols * 0 do bl emit loop home ;
: cls  (dispcls) (concls) ;

test evaluate

cls
aapen-logo
cr
s" V 0.01" tell cr
s" READY" tell cr

quit
