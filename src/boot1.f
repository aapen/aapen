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



( find the word after the given one )

: after ( word -- next-word )
  here @                        ( address of the end of the last compiled word )
  latest @                      ( word last curr )
  begin
    2 pick                      ( word last curr word )
    over                        ( word last curr word curr )
    <>                          ( word last curr word<>curr? )
  while                         ( word last curr )
    nip                         ( word curr )
    dup @                       ( word curr prev -- which becomes: word last curr )
  repeat
  drop
  nip
;

( 'forget word' deletes the definition of 'word' from the dictionary 
  and everything defined after it, including any variables and other 
  memory allocated after.

  The implementation is very simple - we look up the word, which returns
  the dictionary entry address. Then we set HERE to point to that address,
  so in effect all future allocations and definitions will overwrite memory
  starting at the word.  We also need to set LATEST to point to the previous word.

  You should not try to forget built-in words. 

  xxx: because we wrote variable to store the variable in memory allocated before 
  the word, in the current implementation 'variable foo forget foo' will leak 1 cell 
  of memory.
)

: forget
	word find	( find the word, gets the dictionary entry address )
	dup @ latest !	( set latest to point to the previous word )
	here !		( and store here with the dictionary address )
;

: forget-latest
	latest @	( get the most recent word defined )
	dup @ latest !	( get the previous word )
	here !		( and move here back to that prevous word )
;


( Given a word address, return the hidden flag. )

: ?hidden  ( waddr -- hidden-flag )
	8 +		( skip over the link pointer )
	c@		( get the flags byte )
	f_hidden and	( mask the f_hidden flag and return it -- as a truth value )
;

( Given a word address, return the immediate flag. )

: ?immediate ( waddr -- immed-flag )

	8 +		( skip over the link pointer )
	c@		( get the flags byte )
	f_immed and	( mask the F_IMMED flag and return it -- as a truth value )
;

( Given a word address, return the name of the word. )

: id. ( waddr -- len addr )
	9 +		( skip over the link pointer )
	dup c@		( get the length byte )

	begin
		dup 0>		( length > 0? )
	while
		swap 1+		( addr len -- len addr+1 )
		dup c@		( len addr -- len addr char | get the next character)
		emit		( len addr char -- len addr | and print it)
		swap 1-		( len addr -- addr len-1    | subtract one from length )
	repeat
	2drop		( len addr -- )
;

( Read a word name and find it in the dictionary )

: ?word  ( <word> -- w-addr ) word find ;

( Prints the n most recent words in the dictionary.
  Does not print hidden words. )

: recent-words ( n -- )
	latest @                ( n latest )
	begin
		?dup		( while link pointer is not null )
	while
		dup ?hidden not if	( ignore hidden words )
			dup id.		( but if not hidden, print the word )
			space
		then
		@		( dereference the link pointer - go to previous word )
                swap 1-         ( word-p n )
                dup not if      ( printed enough? )
                        2drop
                        cr
                        exit
                then
                swap
	repeat
        drop
	cr
;

( Prints all the words defined in the dictionary, most recently defined first. )

: words ( -- )
  0xefffffff recent-words
;

( see decompiles a FORTH word.

  We search for the dictionary entry of the word, then search again for the next
  word -- effectively, the end of the compiled word.  This results in two pointers:

  +---------+---+---+---+---+------------+------------+------------+------------+
  | LINK    | 3 | T | E | N | DOCOL      | LIT        | 10         | EXIT       |
  +---------+---+---+---+---+------------+------------+------------+------------+
   ^									       ^
   |									       |
  Start of word							      End of word

  With this information we can have a go at decompiling the word.  We need to
  recognise "meta-words" like LIT, LITSTRING, BRANCH, etc. and treat those separately.
)

: see
	word find	( find the dictionary entry to decompile )

        ?dup 0= if ." not found " exit then

	( Now we search again, looking for the next word in the dictionary.  This gives us
	  the length of the word that we will be decompiling.  Well, mostly it does. )
        dup after swap                 ( end-of-word start-of-word )

	( begin the definition with : NAME [IMMEDIATE] )
	':' emit space dup id. space
	dup ?immediate if ." immediate " then

        dup >cfa @ dovar = if
          ." <var> " >dfa dup @ . ." @0x" .x cr
          drop
          exit
        then

        dup >cfa @ docol = if
	  >dfa		( get the data address, ie. points after DOCOL | end-of-word start-of-data )
        else
          ( This might be a primitive, or it might be a child word given 
	    behavior by `does>`. I'm not sure how to tell the difference here.

            If it is a does> child word then the current word's >cfa points to 
	    some assembly inlined in the parent. To decompile this we need to 
	    find the correct start & end to use for the parent word. The start
	    will be the target of the current word's >cfa plus 32
            bytes -- that's due to the 8 instruction shim that gets inlined 
	    into the parent word by does>. To find the end, we have to do 
	    _another_ search. This time instead of `find` we need to look for a 
	    word that contains the >cfa's target address and get it's end.)

          dup >dfa ." 0x" .x ." ( does 0x" dup >cfa @ .x  ." ) "
          nip                   ( start-of-child-word )
          >cfa @ 0d32 +         ( thread-of-parent-word )
          dup cfa> after swap   ( end-of-parent-word thread-of-parent-word )
        then

	( now we start decompiling until we hit the end of the word )
	begin		( end start )
		2dup >
	while
		dup @		( end start codeword )

		case
		' lit of		( is it lit ? )
			cell+ dup @		( get next word which is the integer constant )
			.			( and print it )
		endof
		' litstring of		( is it litstring ? )
			[ char s ] literal emit '"' emit space ( print s"<space> )
			cell+ dup @		( get the length word )
			swap cell+ swap		( end start+8 length )
			2dup tell		( print the string )
			'"' emit space		( finish the string with a final quote )
			+ aligned		( end start+8+len, aligned )
			1 cells -		( because we're about to add 8 below )
		endof
		' 0branch of		( is it 0branch ? )
			." 0branch ( "
			cell+ dup @		( print the offset )
			.
			." ) "
		endof
		' branch of		( is it branch ? )
			." branch ( "
			cell+ dup @		( print the offset )
			.
			." ) "
		endof
		' ' of			( is it ' <tick> ? )
			[ char ' ] literal emit space
			cell+ dup @		( get the next codeword )
			cfa>			( and force it to be printed as a dictionary entry )
			id. space
		endof
                ' (does>) of            ( is it does>?)
                        ." does> "
                        0d32 +                  ( skip the shim )
                endof
		' exit of		( is it exit? )
			( we expect the last word to be exit, and if it is then we don't print it
			  because exit is normally implied by ;.  exit can also appear in the middle
			  of words, and then it needs to be printed. )
			2dup			( end start end start )
			cell+			( end start end start+4 )
			<> if			( end start | we're not at the end )
				." exit "
			then
		endof
					( default case: )
			dup			( in the default case we always need to dup before using )
			cfa>			( look up the codeword to get the dictionary entry )
			id. space		( and print it )
		endcase

		cell+		( end start+8 )
	repeat

	';' emit cr

	2drop		( restore stack )
;

( dump out the contents of memory, in the 'traditional' hexdump format.
  Note that the parameters to dump -- address, length -- are compatible with string words
  such as WORD and S".

  You can dump out the raw code for the last word you defined by doing something like:
  latest @ 128 dump)

: dump		( addr len -- )
	base @ -rot		( base addr len | save the current base at the bottom of the stack )
	hex			( and switch to hexadecimal mode )

	begin
		dup 0>		( while len > 0 )
	while
		over 8 u.r0	( print the address | base addr len )
		space

		( print up to 16 words on this line )
		2dup		( base addr len addr len )
		1- 15 and 1+	( base addr len addr linelen )
		begin
			dup 0>		( while linelen > 0 )
		while
			swap		( base addr len linelen addr )
			dup c@		( base addr len linelen addr byte )
			2 u.r0 space	( base addr len linelen addr | print the byte )
			1+ swap 1-	( base addr len linelen addr -- base addr len addr+1 linelen-1 )
		repeat
		2drop		( base addr len )
                space

		( print the ascii equivalents )
		2dup 1- 15 and 1+ ( base addr len addr linelen )
		begin
			dup 0>		( while linelen > 0)
		while
			swap		( base addr len linelen addr )
			dup c@		( base addr len linelen addr byte )
			dup 32 128 within if	( 32 <= c < 128? )
				emit
			else
				drop '.' emit
			then
			1+ swap 1-	( base addr len linelen addr -- base addr len addr+1 linelen-1 )
		repeat
		2drop		( base addr len )
		cr

		dup 1- 15 and 1+ ( base addr len linelen )
		dup		( base addr len linelen linelen )
		-rot		( base addr linelen len linelen )
		-		( base addr linelen len-linelen )
		-rot		( base len-linelen addr linelen )
		+		( base len-linelen addr+linelen )
		swap		( base addr-linelen len-linelen )
	repeat

	2drop			( base | restore stack )
	base !			( | restore saved base )
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
  ." Next 128 bytes: " cr 48 + 128 dump
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

: array create cells allot does> swap cells + ;

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
mailbox evaluate
sdcard evaluate

cls
aapen-logo
cr
s" V 0.01" tell cr
s" READY" tell cr
quit
