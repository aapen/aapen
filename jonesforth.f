\ -*- text -*-
\
\       Much of the annotation has been removed from the file to expediate processing.
\       See the files in the /annexia/ for the full Literate Code tutorial, it's great!
\
\	ORIGNAL NOTICE ----------------------------------------------------------------------
\
\	A sometimes minimal FORTH compiler and tutorial for Linux / i386 systems. -*- asm -*-
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

: / /MOD SWAP DROP ;
: MOD /MOD DROP ;

: '\n' 10 ;
: BL   32 ;

: NEGATE 0 SWAP - ;

: LITERAL IMMEDIATE ' LIT , , ;  \ takes <word> from the stack and compiles LIT <word>

\ Now we can use [ and ] to insert literals which are calculated at compile time.
\ Within definitions, use [ ... ] LITERAL anywhere that '...' is a constant expression which you
\ would rather only compute once (at compile time, rather than calculating it each time your word runs).
: ':'
	[		\ go into immediate mode (temporarily)
	CHAR :		\ push the number 58 (ASCII code of colon) on the parameter stack
	]		\ go back to compile mode
	LITERAL		\ compile LIT 58 as the definition of ':' word
;
: ';' [ CHAR ; ] LITERAL ;
: '(' [ CHAR ( ] LITERAL ;
: ')' [ CHAR ) ] LITERAL ;
: '"' [ CHAR " ] LITERAL ;
: 'A' [ CHAR A ] LITERAL ;
: '0' [ CHAR 0 ] LITERAL ;
: '-' [ CHAR - ] LITERAL ;
: '.' [ CHAR . ] LITERAL ;

\ While compiling, '[COMPILE] <word>' compiles <word> if it would otherwise be IMMEDIATE.
: [COMPILE] IMMEDIATE
	WORD		\ get the next word
	FIND		\ find it in the dictionary
	>CFA		\ get its codeword
	,		\ and compile that
;

\ RECURSE makes a recursive call to the current word that is being compiled.
: RECURSE IMMEDIATE
	LATEST @	\ LATEST points to the word being compiled at the moment
	>CFA		\ get the codeword
	,		\ compile it
;

\	CONTROL STRUCTURES ----------------------------------------------------------------------
\
\ Please note that the control structures as I have defined them here will only work inside compiled
\ words.  If you try to type in expressions using IF, etc. in immediate mode, then they won't work.
\ Making these work in immediate mode is left as an exercise for the reader.

\ <condition> IF <true-part> THEN <rest>
\ <condition> IF <true-part> ELSE <false-part> THEN
: IF IMMEDIATE
	' 0BRANCH ,	\ compile 0BRANCH
	HERE @		\ save location of the offset on the stack
	0 ,		\ compile a dummy offset
;
: THEN IMMEDIATE
	DUP
	HERE @ SWAP -	\ calculate the offset from the address saved on the stack
	SWAP !		\ store the offset in the back-filled location
;
: ELSE IMMEDIATE
	' BRANCH ,	\ definite branch to just over the false-part
	HERE @		\ save location of the offset on the stack
	0 ,		\ compile a dummy offset
	SWAP		\ now back-fill the original (IF) offset
	DUP		\ same as for THEN word above
	HERE @ SWAP -
	SWAP !
;

\ BEGIN <loop-part> <condition> UNTIL
\ This is like do { <loop-part> } while (<condition>) in the C language
: BEGIN IMMEDIATE
	HERE @		\ save location on the stack
;
: UNTIL IMMEDIATE
	' 0BRANCH ,	\ compile 0BRANCH
	HERE @ -	\ calculate the offset from the address saved on the stack
	,		\ compile the offset here
;

\ BEGIN <loop-part> AGAIN
\ An infinite loop which can only be returned from with EXIT
: AGAIN IMMEDIATE
	' BRANCH ,	\ compile BRANCH
	HERE @ -	\ calculate the offset back
	,		\ compile the offset here
;

\ BEGIN <condition> WHILE <loop-part> REPEAT
\ So this is like a while (<condition>) { <loop-part> } loop in the C language
: WHILE IMMEDIATE
	' 0BRANCH ,	\ compile 0BRANCH
	HERE @		\ save location of the offset2 on the stack
	0 ,		\ compile a dummy offset2
;

: REPEAT IMMEDIATE
	' BRANCH ,	\ compile BRANCH
	SWAP		\ get the original offset (from BEGIN)
	HERE @ - ,	\ and compile it after BRANCH
	DUP
	HERE @ SWAP -	\ calculate the offset2
	SWAP !		\ and back-fill it in the original location
;

\ UNLESS is the same as IF but the test is reversed.
: UNLESS IMMEDIATE
	' NOT ,		\ compile NOT (to reverse the test)
	[COMPILE] IF	\ continue by calling the normal IF
;

\	COMMENTS ----------------------------------------------------------------------
\
\ FORTH allows ( ... ) as comments within function definitions.  This works by having an IMMEDIATE
\ word called ( which just drops input characters until it hits the corresponding ).
: ( IMMEDIATE
	1		\ allowed nested parens by keeping track of depth
	BEGIN
		KEY		\ read next character
		DUP '(' = IF	\ open paren?
			DROP		\ drop the open paren
			1+		\ depth increases
		ELSE
			')' = IF	\ close paren?
				1-		\ depth decreases
			THEN
		THEN
	DUP 0= UNTIL		\ continue until we reach matching close paren, depth 0
	DROP		\ drop the depth counter
;

(
	From now on we can use ( ... ) for comments.

	STACK NOTATION ----------------------------------------------------------------------

	In FORTH style we can also use ( ... -- ... ) to show the effects that a word has on the
	parameter stack.  For example:

	( n -- )	means that the word consumes an integer (n) from the parameter stack.
	( b a -- c )	means that the word uses two integers (a and b, where a is at the top of stack)
				and returns a single integer (c).
	( -- )		means the word has no effect on the stack
)

( Some more complicated stack examples, showing the stack notation. )
: NIP ( x y -- y ) SWAP DROP ;
: TUCK ( x y -- y x y ) SWAP OVER ;
: PICK ( x_u ... x_1 x_0 u -- x_u ... x_1 x_0 x_u )
	1+		( add one because of 'u' on the stack )
	4 *		( multiply by the word size )
	DSP@ +		( add to the stack pointer )
	@    		( and fetch )
;

( With the looping constructs, we can now write SPACES, which writes n spaces to stdout. )
: SPACES	( n -- )
	BEGIN
		DUP 0>		( while n > 0 )
	WHILE
		SPACE		( print a space )
		1-		( until we count down to 0 )
	REPEAT
	DROP
;

( interpret base-b literal value w/o changing BASE, e.g.: 2 # 101 produces 5 )
: #     ( b -- n )
        BASE @ 
        SWAP BASE ! 
        WORD NUMBER 
        DROP SWAP 
        BASE !
;

(
	PRINTING NUMBERS ----------------------------------------------------------------------

	The standard FORTH word . (DOT) is very important.  It takes the number at the top
	of the stack and prints it out.  However first I'm going to implement some lower-level
	FORTH words:

	U.R	( u width -- )	which prints an unsigned number, padded to a certain width
	U.	( u -- )	which prints an unsigned number
	.R	( n width -- )	which prints a signed number, padded to a certain width.

	. and friends obey the current base in the variable BASE, which can range from 2 to 36.
)

( This is the underlying recursive definition of U. It will be redefined below. )
: U.		( u -- )
	BASE @ /MOD	( width rem quot )
	?DUP IF			( if quotient <> 0 then )
		RECURSE		( print the quotient )
	THEN

	( print the remainder )
	DUP 10 < IF
		'0'		( decimal digits 0..9 )
	ELSE
		10 -		( hex and beyond digits A..Z )
		'A'
	THEN
	+
	EMIT
;

(
	FORTH word .S prints the contents of the stack.  It doesn't alter the stack.
	Very useful for debugging.
)
: .S		( -- )
	DSP@		( get current stack pointer )
	BEGIN
		DUP S0 @ <
	WHILE
		DUP @ U.	( print the stack element )
		SPACE
		4+		( move up )
	REPEAT
	DROP
;

( This word returns the width (in characters) of an unsigned number in the current base )
: UWIDTH	( u -- width )
	BASE @ /	( rem quot )
	?DUP IF		( if quotient <> 0 then )
		RECURSE 1+	( return 1+recursive call )
	ELSE
		1		( return 1 )
	THEN
;

: U.R		( u width -- )
	SWAP		( width u )
	DUP		( width u u )
	UWIDTH		( width u uwidth )
	ROT		( u uwidth width )
	SWAP -		( u width-uwidth )
	SPACES
	U.
;

( .R prints a signed number, padded to a certain width. )
: .R		( n width -- )
	SWAP		( width n )
	DUP 0< IF
		NEGATE		( width u )
		1		( save a flag to remember that it was negative | width n 1 )
		SWAP		( width 1 u )
		ROT		( 1 u width )
		1-		( 1 u width-1 )
	ELSE
		0		( width u 0 )
		SWAP		( width 0 u )
		ROT		( 0 u width )
	THEN
	SWAP		( flag width u )
	DUP		( flag width u u )
	UWIDTH		( flag width u uwidth )
	ROT		( flag u uwidth width )
	SWAP -		( flag u width-uwidth )

	SPACES		( flag u )
	SWAP		( u flag )

	IF			( was it negative? print the - character )
		'-' EMIT
	THEN

	U.
;

( Finally we can define word . in terms of .R, with a trailing space. )
: . 0 .R SPACE ;

( The real U., note the trailing space.
  All code beyond this point will use the new definition.
  Old code, including this definition, continues to use the old version.  )
: U. U. SPACE ;

( ? fetches the integer at an address and prints it. )
: ? ( addr -- ) @ . ;

( c a b WITHIN returns true if a <= c and c < b )
(  or define without ifs: OVER - >R - R>  U<  )
: WITHIN
	-ROT		( b c a )
	OVER		( b c a c )
	<= IF
		> IF		( b c -- )
			TRUE
		ELSE
			FALSE
		THEN
	ELSE
		2DROP		( b c -- )
		FALSE
	THEN
;

( DEPTH returns the depth of the stack. )
: DEPTH		( -- n )
	DSP@ S0 @ SWAP - 4 /
;

( ALIGNED takes an address and rounds it up (aligns it) to the next 4 byte boundary. )
: ALIGNED	( addr -- addr )
	3 + 3 INVERT AND	( (addr+3) & ~3 )
;

( ALIGN aligns the HERE pointer, so the next word appended will be aligned properly. )
: ALIGN HERE @ ALIGNED HERE ! ;

(
	STRINGS ----------------------------------------------------------------------

	S" string" is used in FORTH to define strings.  It leaves the address of the string and
	its length on the stack, (length at the top of stack).  The space following S" is the normal
	space between FORTH words and is not a part of the string.
)
( C, appends a byte to the current compiled word. )
: C,
	HERE @ C!	( store the character in the compiled image )
	1 HERE +!	( increment HERE pointer by 1 byte )
;

: S" IMMEDIATE		( -- addr len )
	STATE @ IF	( compiling? )
		' LITS ,	( compile literal string )
		HERE @		( save the address of the length word on the stack )
		0 ,		( dummy length - we don't know what it is yet )
		BEGIN
			KEY 		( get next character of the string )
			DUP '"' <>
		WHILE
			C,		( copy character )
		REPEAT
		DROP		( drop the double quote character at the end )
		DUP		( get the saved address of the length word )
		HERE @ SWAP -	( calculate the length )
		4-		( subtract 4 (because we measured from the start of the length word) )
		SWAP !		( and back-fill the length location )
		ALIGN		( round up to next multiple of 4 bytes for the remaining code )
	ELSE		( immediate mode )
		HERE @		( get the start address of the temporary space )
		BEGIN
			KEY
			DUP '"' <>
		WHILE
			OVER C!		( save next character )
			1+		( increment address )
		REPEAT
		DROP		( drop the final " character )
		HERE @ -	( calculate the length )
		HERE @		( push the start address )
		SWAP 		( addr len )
	THEN
;

(
	." is the print string operator in FORTH.  Example: ." Something to print"
	The space after the operator is the ordinary space required between words and is not
	a part of what is printed.
)
: ." IMMEDIATE		( -- )
	STATE @ IF	( compiling? )
		[COMPILE] S"	( read the string, and compile literal, etc. )
		' TELL ,	( compile the final TELL )
	ELSE
		( In immediate mode, just read characters and print them until we get
		  to the ending double quote. )
		BEGIN
			KEY
			DUP '"' = IF
				DROP	( drop the double quote character )
				EXIT	( return from this function )
			THEN
			EMIT
		AGAIN
	THEN
;

(
	CONSTANTS AND VARIABLES ----------------------------------------------------------------------

	In FORTH, global constants and variables are defined like this:

	10 CONSTANT TEN		when TEN is executed, it leaves the integer 10 on the stack
	VARIABLE VAR		when VAR is executed, it leaves the address of VAR on the stack

	Constants can be read but not written, eg:

	TEN . CR		prints 10

	You can read a variable (in this example called VAR) by doing:

	VAR @			leaves the value of VAR on the stack
	VAR @ . CR		prints the value of VAR
	VAR ? CR		same as above, since ? is the same as @ .

	and update the variable by doing:

	20 VAR !		sets VAR to 20

	Note that variables are uninitialised (but see VALUE later on which provides initialised
	variables with a slightly simpler syntax).
)
: CONSTANT
	WORD		( get the name (the name follows CONSTANT) )
	CREATE		( make the dictionary entry )
	DOCOL ,		( append DOCOL (the codeword field of this word) )
	' LIT ,		( append the codeword LIT )
	,		( append the value on the top of the stack )
	' EXIT ,	( append the codeword EXIT )
;

(
	To make this more general let's define a couple of words which we can use to allocate
	arbitrary memory from the user memory.

	First ALLOT, where n ALLOT allocates n bytes of memory.  (Note when calling this that
	it's a very good idea to make sure that n is a multiple of 4, or at least that next time
	a word is compiled that HERE has been left as a multiple of 4).
)
: ALLOT		( n -- addr )
	HERE @ SWAP	( here n )
	HERE +!		( adds n to HERE, after this the old value of HERE is still on the stack )
;

(
	Second, CELLS.  In FORTH the phrase 'n CELLS ALLOT' means allocate n integers of whatever size
	is the natural size for integers on this machine architecture.  On this 32 bit machine therefore
	CELLS just multiplies the top of stack by 4.
)
: CELLS ( n -- n ) 4 * ;

(
	So now we can define VARIABLE easily in much the same way as CONSTANT above.  Refer to the
	diagram above to see what the word that this creates will look like.
)
: VARIABLE
	1 CELLS ALLOT	( allocate 1 cell of memory, push the pointer to this memory )
	WORD CREATE	( make the dictionary entry (the name follows VARIABLE) )
	DOCOL ,		( append DOCOL (the codeword field of this word) )
	' LIT ,		( append the codeword LIT )
	,		( append the pointer to the new memory )
	' EXIT ,	( append the codeword EXIT )
;

(
	VALUES ----------------------------------------------------------------------

	VALUEs are like VARIABLEs but with a simpler syntax.  You would generally use them when you
	want a variable which is read often, and written infrequently.

	20 VALUE VAL 	creates VAL with initial value 20
	VAL		pushes the value (20) directly on the stack
	30 TO VAL	updates VAL, setting it to 30
	VAL		pushes the value (30) directly on the stack

	Notice that 'VAL' on its own doesn't return the address of the value, but the value itself,
	making values simpler and more obvious to use than variables (no indirection through '@').
	The price is a more complicated implementation, although despite the complexity there is no
	performance penalty at runtime.
)
: VALUE		( n -- )
	WORD CREATE	( make the dictionary entry (the name follows VALUE) )
	DOCOL ,		( append DOCOL )
	' LIT ,		( append the codeword LIT )
	,		( append the initial value )
	' EXIT ,	( append the codeword EXIT )
;

: TO IMMEDIATE	( n -- )
	WORD		( get the name of the value )
	FIND		( look it up in the dictionary )
	>DFA		( get a pointer to the first data field (the 'LIT') )
	4+		( increment to point at the value )
	STATE @ IF	( compiling? )
		' LIT ,		( compile LIT )
		,		( compile the address of the value )
		' ! ,		( compile ! )
	ELSE		( immediate mode )
		!		( update it straightaway )
	THEN
;

( x +TO VAL adds x to VAL )
: +TO IMMEDIATE
	WORD		( get the name of the value )
	FIND		( look it up in the dictionary )
	>DFA		( get a pointer to the first data field (the 'LIT') )
	4+		( increment to point at the value )
	STATE @ IF	( compiling? )
		' LIT ,		( compile LIT )
		,		( compile the address of the value )
		' +! ,		( compile +! )
	ELSE		( immediate mode )
		+!		( update it straightaway )
	THEN
;

(
	PRINTING THE DICTIONARY ----------------------------------------------------------------------

	ID. takes an address of a dictionary entry and prints the word's name.

	For example: LATEST @ ID. would print the name of the last word that was defined.
)
: ID.
	4+		( skip over the link pointer )
	DUP C@		( get the flags/length byte )
	F_LENMASK AND	( mask out the flags - just want the length )

	BEGIN
		DUP 0>		( length > 0? )
	WHILE
		SWAP 1+		( addr len -- len addr+1 )
		DUP C@		( len addr -- len addr char | get the next character)
		EMIT		( len addr char -- len addr | and print it)
		SWAP 1-		( len addr -- addr len-1    | subtract one from length )
	REPEAT
	2DROP		( len addr -- )
;

(
	'WORD word FIND ?HIDDEN' returns true if 'word' is flagged as hidden.

	'WORD word FIND ?IMMEDIATE' returns true if 'word' is flagged as immediate.
)
: ?HIDDEN
	4+		( skip over the link pointer )
	C@		( get the flags/length byte )
	F_HIDDEN AND	( mask the F_HIDDEN flag and return it (as a truth value) )
;
: ?IMMEDIATE
	4+		( skip over the link pointer )
	C@		( get the flags/length byte )
	F_IMMED AND	( mask the F_IMMED flag and return it (as a truth value) )
;

(
	WORDS prints all the words defined in the dictionary, starting with the word defined most recently.
	However it doesn't print hidden words.

	The implementation simply iterates backwards from LATEST using the link pointers.
)
: WORDS
	LATEST @	( start at LATEST dictionary entry )
	BEGIN
		?DUP		( while link pointer is not null )
	WHILE
		DUP ?HIDDEN NOT IF	( ignore hidden words )
			DUP ID.		( but if not hidden, print the word )
			SPACE
		THEN
		@		( dereference the link pointer - go to previous word )
	REPEAT
	CR
;

(
	FORGET ----------------------------------------------------------------------

	So far we have only allocated words and memory.  FORTH provides a rather primitive method
	to deallocate.

	'FORGET word' deletes the definition of 'word' from the dictionary and everything defined
	after it, including any variables and other memory allocated after.
)
: FORGET
	WORD FIND	( find the word, gets the dictionary entry address )
	DUP @ LATEST !	( set LATEST to point to the previous word )
	HERE !		( and store HERE with the dictionary address )
;

(
	CASE ----------------------------------------------------------------------

	CASE...ENDCASE is how we do switch statements in FORTH.  There is no generally
	agreed syntax for this, so I've gone for the syntax mandated by the ISO standard
	FORTH (ANS-FORTH).

		( some value on the stack )
		CASE
		test1 OF ... ENDOF
		test2 OF ... ENDOF
		testn OF ... ENDOF
		... ( default case )
		ENDCASE

	The CASE statement tests the value on the stack by comparing it for equality with
	test1, test2, ..., testn and executes the matching piece of code within OF ... ENDOF.
	If none of the test values match then the default case is executed.  Inside the ... of
	the default case, the value is still at the top of stack (it is implicitly DROP-ed
	by ENDCASE).  When ENDOF is executed it jumps after ENDCASE (ie. there is no "fall-through"
	and no need for a break statement like in C).

	The default case may be omitted.  In fact the tests may also be omitted so that you
	just have a default case, although this is probably not very useful.

	The implementation of CASE...ENDCASE is somewhat non-trivial.  I'm following the
	implementations from http://www.uni-giessen.de/faq/archiv/forthfaq.case_endcase/msg00000.html
)
: CASE IMMEDIATE
	0		( push 0 to mark the bottom of the stack )
;

: OF IMMEDIATE
	' OVER ,	( compile OVER )
	' = ,		( compile = )
	[COMPILE] IF	( compile IF )
	' DROP ,  	( compile DROP )
;

: ENDOF IMMEDIATE
	[COMPILE] ELSE	( ENDOF is the same as ELSE )
;

: ENDCASE IMMEDIATE
	' DROP ,	( compile DROP )

	( keep compiling THEN until we get to our zero marker )
	BEGIN
		?DUP
	WHILE
		[COMPILE] THEN
	REPEAT
;

(
	DECOMPILER ----------------------------------------------------------------------

	CFA> is the opposite of >CFA.  It takes a codeword and tries to find the matching
	dictionary definition.  (In truth, it works with any pointer into a word, not just
	the codeword pointer, and this is needed to do stack traces).

	In this FORTH this is not so easy.  In fact we have to search through the dictionary
	because we don't have a convenient back-pointer (as is often the case in other versions
	of FORTH).  Because of this search, CFA> should not be used when performance is critical,
	so it is only used for debugging tools such as the decompiler and printing stack
	traces.

	This word returns 0 if it doesn't find a match.
)
: CFA>
	LATEST @	( start at LATEST dictionary entry )
	BEGIN
		?DUP		( while link pointer is not null )
	WHILE
		2DUP SWAP	( cfa curr curr cfa )
		< IF		( current dictionary entry < cfa? )
			NIP		( leave curr dictionary entry on the stack )
			EXIT
		THEN
		@		( follow link pointer back )
	REPEAT
	DROP		( restore stack )
	0		( sorry, nothing found )
;

( SEE decompiles a FORTH word. )
: SEE
	WORD FIND	( find the dictionary entry to decompile )

	( Now we search again, looking for the next word in the dictionary.  This gives us
	  the length of the word that we will be decompiling.  (Well, mostly it does). )
	HERE @		( address of the end of the last compiled word )
	LATEST @	( word last curr )
	BEGIN
		2 PICK		( word last curr word )
		OVER		( word last curr word curr )
		<>		( word last curr word<>curr? )
	WHILE			( word last curr )
		NIP		( word curr )
		DUP @		( word curr prev (which becomes: word last curr) )
	REPEAT

	DROP		( at this point, the stack is: start-of-word end-of-word )
	SWAP		( end-of-word start-of-word )

	( begin the definition with : NAME [IMMEDIATE] )
	':' EMIT SPACE DUP ID. SPACE
	DUP ?IMMEDIATE IF ." IMMEDIATE " THEN

	>DFA		( get the data address, ie. points after DOCOL | end-of-word start-of-data )

	( now we start decompiling until we hit the end of the word )
	BEGIN		( end start )
		2DUP >
	WHILE
		DUP @		( end start codeword )

		CASE
		' LIT OF		( is it LIT ? )
			4 + DUP @		( get next word which is the integer constant )
			.			( and print it )
		ENDOF
		' LITS OF		( is it LITS ? )
			[ CHAR S ] LITERAL EMIT '"' EMIT SPACE ( print S"<space> )
			4 + DUP @		( get the length word )
			SWAP 4 + SWAP		( end start+4 length )
			2DUP TELL		( print the string )
			'"' EMIT SPACE		( finish the string with a final quote )
			+ ALIGNED		( end start+4+len, aligned )
			4 -			( because we're about to add 4 below )
		ENDOF
		' 0BRANCH OF		( is it 0BRANCH ? )
			." 0BRANCH ( "
			4 + DUP @		( print the offset )
			.
			." ) "
		ENDOF
		' BRANCH OF		( is it BRANCH ? )
			." BRANCH ( "
			4 + DUP @		( print the offset )
			.
			." ) "
		ENDOF
		' ' OF			( is it ' (TICK) ? )
			[ CHAR ' ] LITERAL EMIT SPACE
			4 + DUP @		( get the next codeword )
			CFA>			( and force it to be printed as a dictionary entry )
			ID. SPACE
		ENDOF
		' EXIT OF		( is it EXIT? )
			( We expect the last word to be EXIT, and if it is then we don't print it
			  because EXIT is normally implied by ;.  EXIT can also appear in the middle
			  of words, and then it needs to be printed. )
			2DUP			( end start end start )
			4 +			( end start end start+4 )
			<> IF			( end start | we're not at the end )
				." EXIT "
			THEN
		ENDOF
					( default case: )
			DUP			( in the default case we always need to DUP before using )
			CFA>			( look up the codeword to get the dictionary entry )
			ID. SPACE		( and print it )
		ENDCASE

		4 +		( end start+4 )
	REPEAT

	';' EMIT CR

	2DROP		( restore stack )
;

(
	EXECUTION TOKENS ----------------------------------------------------------------------

	Standard FORTH defines a concept called an 'execution token' (or 'xt') which is very
	similar to a function pointer in C.  We map the execution token to a codeword address.

	There is one assembler primitive for execution tokens, EXECUTE ( xt -- ), which runs them.

	You can make an execution token for any word FOO, like this:

		['] FOO

	More useful is to define anonymous words and/or to assign xt's to variables.

	To define an anonymous word (and push its xt on the stack) use :NONAME ... ; as in this
	example:

		:NONAME ." anon word was called" CR ;	\ pushes xt on the stack
		DUP EXECUTE EXECUTE			\ executes the anon word twice

	Stack parameters work as expected:

		:NONAME ." called with parameter " . CR ;
		DUP
		10 SWAP EXECUTE		\ prints 'called with parameter 10'
		20 SWAP EXECUTE		\ prints 'called with parameter 20'

	A good way to keep track of the xt (and thus avoid a memory leak)
	is to assign it to a CONSTANT, VARIABLE or VALUE:

		0 VALUE ANON
		:NONAME ." anon word was called" CR ; TO ANON
		ANON EXECUTE
		ANON EXECUTE

	Another use of :NONAME is to create an array of functions which can be called quickly
	(think: fast switch statement).  This example is adapted from the ANS FORTH standard:

		10 CELLS ALLOT CONSTANT CMD-TABLE
		: SET-CMD CELLS CMD-TABLE + ! ;
		: CALL-CMD CELLS CMD-TABLE + @ EXECUTE ;

		:NONAME ." alternate 0 was called" CR ;	 0 SET-CMD
		:NONAME ." alternate 1 was called" CR ;	 1 SET-CMD
			\ etc...
		:NONAME ." alternate 9 was called" CR ;	 9 SET-CMD

		0 CALL-CMD
		1 CALL-CMD
)

: :NONAME
	0 0 CREATE	( create a word with no name - we need a dictionary header because ; expects it )
	HERE @		( current HERE value is the address of the codeword, ie. the xt )
	DOCOL ,		( compile DOCOL (the codeword) )
	]		( go into compile mode )
;

: ['] IMMEDIATE
	' LIT ,		( compile LIT )
;

(
	EXCEPTIONS ----------------------------------------------------------------------

	Amazingly enough, exceptions can be implemented directly in FORTH, in fact rather easily.

	The general usage is as follows:

		: FOO ( n -- ) THROW ;

		: TEST-EXCEPTIONS
			25 ['] FOO CATCH	\ execute 25 FOO, catching any exception
			?DUP IF
				." called FOO and it threw exception number: "
				. CR
				DROP		\ we have to drop the argument of FOO (25)
			THEN
		;
		\ prints: called FOO and it threw exception number: 25

	CATCH runs an execution token and detects whether it throws any exception or not.  The
	stack signature of CATCH is rather complicated:

		( a_n-1 ... a_1 a_0 xt -- r_m-1 ... r_1 r_0 0 )		if xt did NOT throw an exception
		( a_n-1 ... a_1 a_0 xt -- ?_n-1 ... ?_1 ?_0 e )		if xt DID throw exception 'e'

	where a_i and r_i are the (arbitrary number of) argument and return stack contents
	before and after xt is EXECUTEd.  Notice in particular the case where an exception
	is thrown, the stack pointer is restored so that there are n of _something_ on the
	stack in the positions where the arguments a_i used to be.  We don't really guarantee
	what is on the stack -- perhaps the original arguments, and perhaps other nonsense --
	it largely depends on the implementation of the word that was executed.

	THROW, ABORT and a few others throw exceptions.

	Exception numbers are non-zero integers.  By convention the positive numbers can be used
	for app-specific exceptions and the negative numbers have certain meanings defined in
	the ANS FORTH standard.  (For example, -1 is the exception thrown by ABORT).

	0 THROW does nothing.  This is the stack signature of THROW:

		( 0 -- )
		( * e -- ?_n-1 ... ?_1 ?_0 e )	the stack is restored to the state from the corresponding CATCH

	Exceptions are a relatively lightweight mechanism in FORTH.
)

: EXCEPTION-MARKER
	RDROP			( drop the original parameter stack pointer )
	0			( there was no exception, this is the normal return path )
;

: CATCH		( xt -- exn? )
	DSP@ 4+ >R		( save parameter stack pointer (+4 because of xt) on the return stack )
	' EXCEPTION-MARKER 4+	( push the address of the RDROP inside EXCEPTION-MARKER ... )
	>R			( ... on to the return stack so it acts like a return address )
	EXECUTE			( execute the nested function )
;

: THROW		( n -- )
	?DUP IF			( only act if the exception code <> 0 )
		RSP@ 			( get return stack pointer )
		BEGIN
			DUP R0 4- <		( RSP < R0 )
		WHILE
			DUP @			( get the return stack entry )
			' EXCEPTION-MARKER 4+ = IF	( found the EXCEPTION-MARKER on the return stack )
				4+			( skip the EXCEPTION-MARKER on the return stack )
				RSP!			( restore the return stack pointer )

				( Restore the parameter stack. )
				DUP DUP DUP		( reserve some working space so the stack for this word
							  doesn't coincide with the part of the stack being restored )
				R>			( get the saved parameter stack pointer | n dsp )
				4-			( reserve space on the stack to store n )
				SWAP OVER		( dsp n dsp )
				!			( write n on the stack )
				DSP! EXIT		( restore the parameter stack pointer, immediately exit )
			THEN
			4+
		REPEAT

		( No matching catch - print a message and restart the INTERPRETer. )
		DROP

		CASE
		0 1- OF	( ABORT )
			." ABORTED" CR
		ENDOF
			( default case )
			." UNCAUGHT THROW "
			DUP . CR
		ENDCASE
		QUIT
	THEN
;

: ABORT		( -- )
	0 1- THROW
;

( Print a stack trace by walking up the return stack. )
: PRINT-STACK-TRACE
	RSP@				( start at caller of this function )
	BEGIN
		DUP R0 4- <		( RSP < R0 )
	WHILE
		DUP @			( get the return stack entry )
		CASE
		' EXCEPTION-MARKER 4+ OF	( is it the exception stack frame? )
			." CATCH ( DSP="
			4+ DUP @ U.		( print saved stack pointer )
			." ) "
		ENDOF
						( default case )
			DUP
			CFA>			( look up the codeword to get the dictionary entry )
			?DUP IF			( and print it )
				2DUP			( dea addr dea )
				ID.			( print word from dictionary entry )
				[ CHAR + ] LITERAL EMIT
				SWAP >DFA 4+ - .	( print offset )
			THEN
		ENDCASE
		4+			( move up the stack )
	REPEAT
	DROP
	CR
;

( UNUSED returns the number of cells remaining in the user memory (data segment). )
: UNUSED	( -- n )
	PAD 		( the scratch-pad immediately follows the data segment )
	HERE @		( get current position in data segment )
	- 4 /		( returns number of 4-byte cells )
;

( Print the version and OK prompt. )
: WELCOME
	S" TEST-MODE" FIND NOT IF
		." JONESFORTH VERSION " VERSION . CR
		UNUSED . ." CELLS REMAINING" CR
		." OK "
	THEN
;

WELCOME
HIDE WELCOME
