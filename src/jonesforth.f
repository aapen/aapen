\ -*- text -*-
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
\	SETTING UP ----------------------------------------------------------------------
\
\	Let's get a few housekeeping things out of the way.  Firstly because I need to draw lots of
\	ASCII-art diagrams to explain concepts, the best way to look at this is using a window which
\	uses a fixed width font and is at least this wide:
\
\<------------------------------------------------------------------------------------------------------------------------>
\
\	Secondly make sure TABS are set to 8 characters.  The following should be a vertical
\	line.  If not, sort out your tabs.
\
\		|
\	        |
\	    	|
\
\	Thirdly I assume that your screen is at least 50 characters high.
\
\	START OF FORTH CODE ----------------------------------------------------------------------
\
\	We've now reached the stage where the FORTH system is running and self-hosting.  All further
\	words can be written as FORTH itself, including words like IF, THEN, .", etc which in most
\	languages would be considered rather fundamental.
\
\	Some notes about the code:
\
\	I use indenting to show structure.  The amount of whitespace has no meaning to FORTH however
\	except that you must use at least one whitespace character between words, and words themselves
\	cannot contain whitespace.
\
\	FORTH is case-sensitive.  Use capslock!

\ The primitive word /MOD (DIVMOD) leaves both the quotient and the remainder on the stack.  (On
\ i386, the idivl instruction gives both anyway).  Now we can define the / and MOD in terms of /MOD
\ and a few other primitives.
: / /mod swap drop ;
: mod /mod drop ;

\ Define some character constants
: '\n' 10 ;
: '\r' 13 ;
: bl   32 ; \ bl (BLank) is a standard FORTH word for space.

\ cr prints a carriage return
: cr '\r' emit '\n' emit ;

\ space prints a space
: space bl emit ;


\ The 2... versions of the standard operators work on pairs of stack entries.  They're not used
\ very commonly so not really worth writing in assembler.  Here is how they are defined in FORTH.
: 2dup over over ;
: 2drop drop drop ;

\ More standard FORTH words.
: 2* 2 * ;
: 2/ 2 / ;

\ Inc and dec by one CPU word size (64 bits)
: 8+ 8 + ;
: 8- 8 - ;

\ negate leaves the negative of a number on the stack.
: negate 0 swap - ;

\ Standard words for booleans.
: true  1 ;
: false 0 ;
: not   0= ;

\ literal takes whatever is on the stack and compiles lit <foo>
: literal immediate
	' lit ,		\ compile lit
	,		\ compile the literal itself (from the stack)
	;

\ Now we can use [ and ] to insert literals which are calculated at compile time.  (Recall that
\ [ and ] are the FORTH words which switch into and out of immediate mode.)
\ Within definitions, use [ ... ] LITERAL anywhere that '...' is a constant expression which you
\ would rather only compute once (at compile time, rather than calculating it each time your word runs).
: ':'
	[		\ go into immediate mode (temporarily)
	char :		\ push the number 58 (ASCII code of colon) on the parameter stack
	]		\ go back to compile mode
	literal		\ compile lit 58 as the definition of ':' word
;

\ A few more character constants defined the same way as above.
: ';' [ char ; ] literal ;
: '(' [ char ( ] literal ;
: ')' [ char ) ] literal ;
: '"' [ char " ] literal ;
: 'A' [ char A ] literal ;
: '0' [ char 0 ] literal ;
: '-' [ char - ] literal ;
: '.' [ char . ] literal ;

\ while compiling, '[compile] word' compiles 'word' if it would otherwise be IMMEDIATE.
: [compile] immediate
	word		\ get the next word
	find		\ find it in the dictionary
	>cfa		\ get its codeword
	,		\ and compile that
;

\ recurse makes a recursive call to the current word that is being compiled.
\
\ Normally while a word is being compiled, it is marked HIDDEN so that references to the
\ same word within are calls to the previous definition of the word.  However we still have
\ access to the word which we are currently compiling through the LATEST pointer so we
\ can use that to compile a recursive call.
: recurse immediate
	latest @	\ latest points to the word being compiled at the moment
	>cfa		\ get the codeword
	,		\ compile it
;

\	CONTROL STRUCTURES ----------------------------------------------------------------------
\
\ So far we have defined only very simple definitions.  Before we can go further, we really need to
\ make some control structures, like IF ... THEN and loops.  Luckily we can define arbitrary control
\ structures directly in FORTH.
\
\ Please note that the control structures as I have defined them here will only work inside compiled
\ words.  If you try to type in expressions using IF, etc. in immediate mode, then they won't work.
\ Making these work in immediate mode is left as an exercise for the reader.

\ condition IF true-part THEN rest
\	-- compiles to: --> condition 0BRANCH OFFSET true-part rest
\	where OFFSET is the offset of 'rest'
\ condition IF true-part ELSE false-part THEN
\ 	-- compiles to: --> condition 0BRANCH OFFSET true-part BRANCH OFFSET2 false-part rest
\	where OFFSET if the offset of false-part and OFFSET2 is the offset of rest

\ IF is an IMMEDIATE word which compiles 0BRANCH followed by a dummy offset, and places
\ the address of the 0BRANCH on the stack.  Later when we see THEN, we pop that address
\ off the stack, calculate the offset, and back-fill the offset.
: if immediate
	' 0branch ,	\ compile 0branch
	here @		\ save location of the offset on the stack
	0 ,		\ compile a dummy offset
;

: then immediate
	dup
	here @ swap -	\ calculate the offset from the address saved on the stack
	swap !		\ store the offset in the back-filled location
;

: else immediate
	' branch ,	\ definite branch to just over the false-part
	here @		\ save location of the offset on the stack
	0 ,		\ compile a dummy offset
	swap		\ now back-fill the original (if) offset
	dup		\ same as for then word above
	here @ swap -
	swap !
;

\ begin loop-part condition until
\	-- compiles to: --> loop-part condition 0branch offset
\	where offset points back to the loop-part
\ This is like do { loop-part } while (condition) in the C language
: begin immediate
	here @		\ save location on the stack
;

: until immediate
	' 0branch ,	\ compile 0branch
	here @ -	\ calculate the offset from the address saved on the stack
	,		\ compile the offset here
;

\ begin loop-part again
\	-- compiles to: --> loop-part branch offset
\	where offset points back to the loop-part
\ In other words, an infinite loop which can only be returned from with EXIT
: again immediate
	' branch ,	\ compile branch
	here @ -	\ calculate the offset back
	,		\ compile the offset here
;

\ begin condition while loop-part repeat
\	-- compiles to: --> condition 0branch offset2 loop-part branch offset
\	where offset points back to condition (the beginning) and offset2 points to after the whole piece of code
\ So this is like a while (condition) { loop-part } loop in the C language
: while immediate
	' 0branch ,	\ compile 0branch
	here @		\ save location of the offset2 on the stack
	0 ,		\ compile a dummy offset2
;

: repeat immediate
	' branch ,	\ compile branch
	swap		\ get the original offset (from begin)
	here @ - ,	\ and compile it after branch
	dup
	here @ swap -	\ calculate the offset2
	swap !		\ and back-fill it in the original location
;

\ unless is the same as if but the test is reversed.
\
\ note the use of [compile]: since if is immediate we don't want it to be executed while unless
\ is compiling, but while unless is running (which happens to be when whatever word using unless is
\ being compiled -- whew!).  So we use [compile] to reverse the effect of marking if as immediate.
\ this trick is generally used when we want to write our own control words without having to
\ implement them all in terms of the primitives 0branch and branch, but instead reusing simpler
\ control words like (in this instance) if.
: unless immediate
	' not ,		\ compile not (to reverse the test)
	[compile] if	\ continue by calling the normal if
;

\	COMMENTS ----------------------------------------------------------------------
\
\ FORTH allows ( ... ) as comments within function definitions.  This works by having an immediate
\ word called ( which just drops input characters until it hits the corresponding ).
: ( immediate
	1		\ allowed nested parens by keeping track of depth
	begin
                brk
		key		\ read next character
		dup '(' = if	\ open paren?
			drop		\ drop the open paren
			1+		\ depth increases
		else
			')' = if	\ close paren?
				1-		\ depth decreases
			then
		then
	dup 0= until		\ continue until we reach matching close paren, depth 0
	drop		\ drop the depth counter
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
: nip ( x y -- y ) swap drop ;
: tuck ( x y -- y x y ) swap over ;
: pick ( x_u ... x_1 x_0 u -- x_u ... x_1 x_0 x_u )
	1+		( add one because of 'u' on the stack )
	8 *		( multiply by the word size )
	dsp@ +		( add to the stack pointer )
	@    		( and fetch )
;

( With the looping constructs, we can now write SPACES, which writes n spaces to stdout. )
: spaces	( n -- )
	begin
		dup 0>		( while n > 0 )
	while
		space		( print a space )
		1-		( until we count down to 0 )
	repeat
	drop
;

( Standard words for manipulating BASE. )
: decimal ( -- ) 10 base ! ;
: hex ( -- ) 16 base ! ;

(
	PRINTING NUMBERS ----------------------------------------------------------------------

	The standard FORTH word . (DOT) is very important.  It takes the number at the top
	of the stack and prints it out.  However first I'm going to implement some lower-level
	FORTH words:

	U.R	( u width -- )	which prints an unsigned number, padded to a certain width
	U.	( u -- )	which prints an unsigned number
	.R	( n width -- )	which prints a signed number, padded to a certain width.

	For example:
		-123 6 .R
	will print out these characters:
		<space> <space> - 1 2 3

	In other words, the number padded left to a certain number of characters.

	The full number is printed even if it is wider than width, and this is what allows us to
	define the ordinary functions U. and . (we just set width to zero knowing that the full
	number will be printed anyway).

	Another wrinkle of . and friends is that they obey the current base in the variable BASE.
	BASE can be anything in the range 2 to 36.

	While we're defining . &c we can also define .S which is a useful debugging tool.  This
	word prints the current stack (non-destructively) from top to bottom.
)

( This is the underlying recursive definition of U. )
: u.		( u -- )
	base @ /mod	( width rem quot )
	?dup if			( if quotient <> 0 then )
		recurse		( print the quotient )
	then

	( print the remainder )
	dup 10 < if
		'0'		( decimal digits 0..9 )
	else
		10 -		( hex and beyond digits a..z )
		'A'
	then
	+
	emit
;

(
	FORTH word .S prints the contents of the stack.  It doesn't alter the stack.
	Very useful for debugging.
)
: .s		( -- )
	dsp@		( get current stack pointer )
	begin
		dup s0 @ <
	while
		dup @ u.	( print the stack element )
		space
		8+		( move up )
	repeat
	drop
;

( This word returns the width (in characters) of an unsigned number in the current base )
: uwidth	( u -- width )
	base @ /	( rem quot )
	?dup if		( if quotient <> 0 then )
		recurse 1+	( return 1+recursive call )
	else
		1		( return 1 )
	then
;

: u.r		( u width -- )
	swap		( width u )
	dup		( width u u )
	uwidth		( width u uwidth )
	rot		( u uwidth width )
	swap -		( u width-uwidth )
	( At this point if the requested width is narrower, we'll have a negative number on the stack.
	  Otherwise the number on the stack is the number of spaces to print.  But SPACES won't print
	  a negative number of spaces anyway, so it's now safe to call SPACES ... )
	spaces
	( ... and then call the underlying implementation of U. )
	u.
;

(
	.R prints a signed number, padded to a certain width.  We can't just print the sign
	and call U.R because we want the sign to be next to the number ('-123' instead of '-  123').
)
: .r		( n width -- )
	swap		( width n )
	dup 0< if
		negate		( width u )
		1		( save a flag to remember that it was negative | width u 1 )
		swap		( width 1 u )
		rot		( 1 u width )
		1-		( 1 u width-1 )
	else
		0		( width u 0 )
		swap		( width 0 u )
		rot		( 0 u width )
	then
	swap		( flag width u )
	dup		( flag width u u )
	uwidth		( flag width u uwidth )
	rot		( flag u uwidth width )
	swap -		( flag u width-uwidth )

	spaces		( flag u )
	swap		( u flag )

	if			( was it negative? print the - character )
		'-' emit
	then

	u.
;

( Finally we can define word . in terms of .R, with a trailing space. )
: . 0 .r space ;

( The real U., note the trailing space. )
: u. u. space ;

( ? fetches the integer at an address and prints it. )
: ? ( addr -- ) @ . ;

( c a b WITHIN returns true if a <= c and c < b )
(  or define without ifs: OVER - >R - R>  U<  )
: within
	-rot		( b c a )
	over		( b c a c )
	<= if
		> if		( b c -- )
			true
		else
			false
		then
	else
		2drop		( b c -- )
		false
	then
;

( depth returns the depth of the stack. )
: depth		( -- n )
	s0 @ dsp@ -
	8-			( adjust because S0 was on the stack when we pushed DSP )
;

(
	ALIGNED takes an address and rounds it up (aligns it) to the next 8 byte boundary.
)
: aligned	( addr -- addr )
	7 + 7 invert and	( (addr+7) & ~7 )
;

(
	ALIGN aligns the HERE pointer, so the next word appended will be aligned properly.
)
: align here @ aligned here ! ;

(
	STRINGS ----------------------------------------------------------------------

	s" string" is used in FORTH to define strings.  It leaves the address of the string and
	its length on the stack, (length at the top of stack).  The space following S" is the normal
	space between FORTH words and is not a part of the string.

	This is tricky to define because it has to do different things depending on whether
	we are compiling or in immediate mode.  (Thus the word is marked IMMEDIATE so it can
	detect this and do different things).

	In compile mode we append
		LITSTRING <string length> <string rounded up 4 bytes>
	to the current word.  The primitive LITSTRING does the right thing when the current
	word is executed.

	In immediate mode there isn't a particularly good place to put the string, but in this
	case we put the string at HERE (but we _don't_ change HERE).  This is meant as a temporary
	location, likely to be overwritten soon after.
)

( C, appends a byte to the current compiled word. )
: c,
	here @ c!	( store the character in the compiled image )
	1 here +!	( increment here pointer by 1 byte )
;

: s" immediate		( -- addr len )
	state @ if	( compiling? )
		' litstring ,	( compile litstring )
		here @		( save the address of the length word on the stack )
		0 ,		( dummy length - we don't know what it is yet )
		begin
			key		( get next character of the string )
			dup '"' <>
		while
			c,		( copy character )
		repeat
		drop		( drop the double quote character at the end )
		dup		( get the saved address of the length word )
		here @ swap -	( calculate the length )
		8 -		( subtract 8 (because we measured from the start of the length word) )
		swap !		( and back-fill the length location )
		align		( round up to next multiple of 4 bytes for the remaining code )
	else		( immediate mode )
		here @		( get the start address of the temporary space )
		begin
			key
			dup '"' <>
		while
			over c!		( save next character )
			1+		( increment address )
		repeat
		drop		( drop the final " character )
		here @ -	( calculate the length )
		here @		( push the start address )
		swap		( addr len )
	then
;

(
	." is the print string operator in FORTH.  Example: ." Something to print"
	The space after the operator is the ordinary space required between words and is not
	a part of what is printed.

	In immediate mode we just keep reading characters and printing them until we get to
	the next double quote.

	In compile mode we use S" to store the string, then add TELL afterwards:
		LITSTRING <string length> <string rounded up to 4 bytes> TELL

	It may be interesting to note the use of [COMPILE] to turn the call to the immediate
	word S" into compilation of that word.  It compiles it into the definition of .",
	not into the definition of the word being compiled when this is running (complicated
	enough for you?)
)
: ." immediate		( -- )
	state @ if	( compiling? )
		[compile] s"	( read the string, and compile litstring, etc. )
		' tell ,	( compile the final tell )
	else
		( in immediate mode, just read characters and print them until we get
		  to the ending double quote. )
		begin
			key
			dup '"' = if
				drop	( drop the double quote character )
				exit	( return from this function )
			then
			emit
		again
	then
;


(
	Constants and variables ----------------------------------------------------------------------

	In forth, global constants and variables are defined like this:

	10 constant ten		When ten is executed, it leaves the integer 10 on the stack
	variable var		When var is executed, it leaves the address of var on the stack

	Constants can be read but not written, eg:

	ten . cr		prints 10

	You can read a variable (in this example called var) by doing:

	var @			leaves the value of var on the stack
	var @ . cr		prints the value of var
	var ? cr		same as above, since ? is the same as @ .

	and update the variable by doing:

	20 var !		sets var to 20

	Note that variables are uninitialised (but see value later on which provides initialised
	variables with a slightly simpler syntax).

	How can we define the words CONSTANT and VARIABLE?

	The trick is to define a new word for the variable itself (eg. if the variable was called
	'VAR' then we would define a new word called VAR).  This is easy to do because we exposed
	dictionary entry creation through the CREATE word (part of the definition of : above).
	A call to WORD [TEN] CREATE (where [TEN] means that "TEN" is the next word in the input)
	leaves the dictionary entry:

				   +--- HERE
				   |
				   V
	+---------+---+---+---+---+
	| LINK    | 3 | T | E | N |
	+---------+---+---+---+---+
                   len

	For CONSTANT we can continue by appending DOCOL (the codeword), then LIT followed by
	the constant itself and then EXIT, forming a little word definition that returns the
	constant:

	+---------+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 3 | T | E | N | DOCOL      | LIT        | 10         | EXIT       |
	+---------+---+---+---+---+------------+------------+------------+------------+
                   len              codeword

	Notice that this word definition is exactly the same as you would have got if you had
	written : TEN 10 ;

	Note for people reading the code below: DOCOL is a constant word which we defined in the
	assembler part which returns the value of the assembler symbol of the same name.
)
: constant
	word		( get the name (the name follows constant) )
	create		( make the dictionary entry )
	docol ,		( append docol (the codeword field of this word) )
	' lit ,		( append the codeword lit )
	,		( append the value on the top of the stack )
	' exit ,	( append the codeword exit )
;

(
	VARIABLE is a little bit harder because we need somewhere to put the variable.  There is
	nothing particularly special about the user memory (the area of memory pointed to by HERE
	where we have previously just stored new word definitions).  We can slice off bits of this
	memory area to store anything we want, so one possible definition of VARIABLE might create
	this:

	   +--------------------------------------------------------------+
	   |								  |
	   V								  |
	+---------+---------+---+---+---+---+------------+------------+---|--------+------------+
	| <var>   | LINK    | 3 | V | A | R | DOCOL      | LIT        | <addr var> | EXIT       |
	+---------+---------+---+---+---+---+------------+------------+------------+------------+
        		     len              codeword

	where <var> is the place to store the variable, and <addr var> points back to it.

	To make this more general let's define a couple of words which we can use to allocate
	arbitrary memory from the user memory.

	First ALLOT, where n ALLOT allocates n bytes of memory.  (Note when calling this that
	it's a very good idea to make sure that n is a multiple of 4, or at least that next time
	a word is compiled that HERE has been left as a multiple of 4).
)
: allot		( n -- addr )
	here @ swap	( here n )
	here +!		( adds n to here, after this the old value of here is still on the stack )
;

(
	Second, CELLS.  In FORTH the phrase 'n CELLS ALLOT' means allocate n integers of whatever size
	is the natural size for integers on this machine architecture.  On this 32 bit machine therefore
	CELLS just multiplies the top of stack by 4.
)
: cells ( n -- n ) 8 * ;

(
	So now we can define VARIABLE easily in much the same way as CONSTANT above.  Refer to the
	diagram above to see what the word that this creates will look like.
)
: variable
	1 cells allot	( allocate 1 cell of memory, push the pointer to this memory )
	word create	( make the dictionary entry (the name follows VARIABLE) )
	docol ,		( append docol (the codeword field of this word) )
	' lit ,		( append the codeword lit )
	,		( append the pointer to the new memory )
	' exit ,	( append the codeword exit )
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

	A naive implementation of 'TO' would be quite slow, involving a dictionary search each time.
	But because this is FORTH we have complete control of the compiler so we can compile TO more
	efficiently, turning:
		TO VAL
	into:
		LIT <addr> !
	and calculating <addr> (the address of the value) at compile time.

	Now this is the clever bit.  We'll compile our value like this:

	+---------+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 3 | V | A | L | DOCOL      | LIT        | <value>    | EXIT       |
	+---------+---+---+---+---+------------+------------+------------+------------+
                   len              codeword

	where <value> is the actual value itself.  Note that when VAL executes, it will push the
	value on the stack, which is what we want.

	But what will TO use for the address <addr>?  Why of course a pointer to that <value>:

		code compiled	- - - - --+------------+------------+------------+-- - - - -
		by TO VAL		  | LIT        | <addr>     | !          |
				- - - - --+------------+-----|------+------------+-- - - - -
							     |
							     V
	+---------+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 3 | V | A | L | DOCOL      | LIT        | <value>    | EXIT       |
	+---------+---+---+---+---+------------+------------+------------+------------+
                   len              codeword

	In other words, this is a kind of self-modifying code.

	(Note to the people who want to modify this FORTH to add inlining: values defined this
	way cannot be inlined).
)
: value		( n -- )
	word create	( make the dictionary entry (the name follows value) )
	docol ,		( append docol )
	' lit ,		( append the codeword lit )
	,		( append the initial value )
	' exit ,	( append the codeword exit )
;

: to immediate	( n -- )
	word		( get the name of the value )
	find		( look it up in the dictionary )
	>dfa		( get a pointer to the first data field (the 'lit') )
	8+		( increment to point at the value )
	state @ if	( compiling? )
		' lit ,		( compile lit )
		,		( compile the address of the value )
		' ! ,		( compile ! )
	else		( immediate mode )
		!		( update it straightaway )
	then
;

( x +to val adds x to val )
: +to immediate
	word		( get the name of the value )
	find		( look it up in the dictionary )
	>dfa		( get a pointer to the first data field (the 'lit') )
	8+		( increment to point at the value )
	state @ if	( compiling? )
		' lit ,		( compile lit )
		,		( compile the address of the value )
		' +! ,		( compile +! )
	else		( immediate mode )
		+!		( update it straightaway )
	then
;

(
	PRINTING THE DICTIONARY ----------------------------------------------------------------------

	ID. takes an address of a dictionary entry and prints the word's name.

	For example: LATEST @ ID. would print the name of the last word that was defined.
)
: id.
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

(
	'word word find ?hidden' returns true if 'word' is flagged as hidden.

	'WORD word FIND ?IMMEDIATE' returns true if 'word' is flagged as immediate.
)
: ?hidden
	8 +		( skip over the link pointer )
	c@		( get the flags byte )
	f_hidden and	( mask the f_hidden flag and return it (as a truth value) )
;
: ?immediate
	8 +		( skip over the link pointer )
	c@		( get the flags byte )
	f_immed and	( mask the F_IMMED flag and return it (as a truth value) )
;

(
	WORDS prints all the words defined in the dictionary, starting with the word defined most recently.
	However it doesn't print hidden words.

	The implementation simply iterates backwards from LATEST using the link pointers.
)
: words
	latest @	( start at latest dictionary entry )
	begin
		?dup		( while link pointer is not null )
	while
		dup ?hidden not if	( ignore hidden words )
			dup id.		( but if not hidden, print the word )
			space
		then
		@		( dereference the link pointer - go to previous word )
	repeat
	cr
;

(
	FORGET ----------------------------------------------------------------------

	So far we have only allocated words and memory.  FORTH provides a rather primitive method
	to deallocate.

	'FORGET word' deletes the definition of 'word' from the dictionary and everything defined
	after it, including any variables and other memory allocated after.

	The implementation is very simple - we look up the word (which returns the dictionary entry
	address).  Then we set HERE to point to that address, so in effect all future allocations
	and definitions will overwrite memory starting at the word.  We also need to set LATEST to
	point to the previous word.

	Note that you cannot FORGET built-in words (well, you can try but it will probably cause
	a segfault).

	XXX: Because we wrote VARIABLE to store the variable in memory allocated before the word,
	in the current implementation VARIABLE FOO FORGET FOO will leak 1 cell of memory.
)
: forget
	word find	( find the word, gets the dictionary entry address )
	dup @ latest !	( set latest to point to the previous word )
	here !		( and store here with the dictionary address )
;

(
	DUMP ----------------------------------------------------------------------

	DUMP is used to dump out the contents of memory, in the 'traditional' hexdump format.

	Notice that the parameters to DUMP (address, length) are compatible with string words
	such as WORD and S".

	You can dump out the raw code for the last word you defined by doing something like:

		LATEST @ 128 DUMP
)
: dump		( addr len -- )
        cr
	base @ -rot		( base addr len | save the current base at the bottom of the stack )
	hex			( and switch to hexadecimal mode )

	begin
		dup 0>		( while len > 0 )
	while
		over 8 u.r	( print the address | base addr len )
		space

		( print up to 16 words on this line )
		2dup		( base addr len addr len )
		1- 15 and 1+	( base addr len addr linelen )
		begin
			dup 0>		( while linelen > 0 )
		while
			swap		( base addr len linelen addr )
			dup c@		( base addr len linelen addr byte )
			2 .r space	( base addr len linelen addr | print the byte )
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

	An example (assuming that 'q', etc. are words which push the ASCII value of the letter
	on the stack):

		0 VALUE QUIT
		0 VALUE SLEEP
		KEY CASE
			'q' OF 1 TO QUIT ENDOF
			's' OF 1 TO SLEEP ENDOF
			( default case: )
			." Sorry, I didn't understand key <" DUP EMIT ." >, try again." CR
		ENDCASE

	(In some versions of FORTH, more advanced tests are supported, such as ranges, etc.
	Other versions of FORTH need you to write OTHERWISE to indicate the default case.
	As I said above, this FORTH tries to follow the ANS FORTH standard).

	The implementation of CASE...ENDCASE is somewhat non-trivial.  I'm following the
	implementations from here:
	http://www.uni-giessen.de/faq/archiv/forthfaq.case_endcase/msg00000.html

	The general plan is to compile the code as a series of IF statements:

	CASE				(push 0 on the immediate-mode parameter stack)
	test1 OF ... ENDOF		test1 OVER = IF DROP ... ELSE
	test2 OF ... ENDOF		test2 OVER = IF DROP ... ELSE
	testn OF ... ENDOF		testn OVER = IF DROP ... ELSE
	... ( default case )		...
	ENDCASE				DROP THEN [THEN [THEN ...]]

	The CASE statement pushes 0 on the immediate-mode parameter stack, and that number
	is used to count how many THEN statements we need when we get to ENDCASE so that each
	IF has a matching THEN.  The counting is done implicitly.  If you recall from the
	implementation above of IF, each IF pushes a code address on the immediate-mode stack,
	and these addresses are non-zero, so by the time we get to ENDCASE the stack contains
	some number of non-zeroes, followed by a zero.  The number of non-zeroes is how many
	times IF has been called, so how many times we need to match it with THEN.

	This code uses [COMPILE] so that we compile calls to IF, ELSE, THEN instead of
	actually calling them while we're compiling the words below.

	As is the case with all of our control structures, they only work within word
	definitions, not in immediate mode.
)
: case immediate
	0		( push 0 to mark the bottom of the stack )
;

: of immediate
	' over ,	( compile over )
	' = ,		( compile = )
	[compile] if	( compile if )
	' drop ,  	( compile drop )
;

: endof immediate
	[compile] else	( endof is the same as else )
;

: endcase immediate
	' drop ,	( compile drop )

	( keep compiling then until we get to our zero marker )
	begin
		?dup
	while
		[compile] then
	repeat
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
: cfa>
	latest @	( start at latest dictionary entry )
	begin
		?dup		( while link pointer is not null )
	while
		2dup swap	( cfa curr curr cfa )
		< if		( current dictionary entry < cfa? )
			nip		( leave curr dictionary entry on the stack )
			exit
		then
		@		( follow link pointer back )
	repeat
	drop		( restore stack )
	0		( sorry, nothing found )
;

(
	SEE decompiles a FORTH word.

	We search for the dictionary entry of the word, then search again for the next
	word (effectively, the end of the compiled word).  This results in two pointers:

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

        dup 0= if ." not found " exit then

	( Now we search again, looking for the next word in the dictionary.  This gives us
	  the length of the word that we will be decompiling.  (Well, mostly it does). )
	here @		( address of the end of the last compiled word )
	latest @	( word last curr )
	begin
		2 pick		( word last curr word )
		over		( word last curr word curr )
		<>		( word last curr word<>curr? )
	while			( word last curr )
		nip		( word curr )
		dup @		( word curr prev (which becomes: word last curr) )
	repeat

	drop		( at this point, the stack is: start-of-word end-of-word )
	swap		( end-of-word start-of-word )

	( begin the definition with : NAME [IMMEDIATE] )
	':' emit space dup id. space
	dup ?immediate if ." immediate " then

	>dfa		( get the data address, ie. points after DOCOL | end-of-word start-of-data )

	( now we start decompiling until we hit the end of the word )
	begin		( end start )
		2dup >
	while
		dup @		( end start codeword )

		case
		' lit of		( is it lit ? )
			8 + dup @		( get next word which is the integer constant )
			.			( and print it )
		endof
		' litstring of		( is it litstring ? )
			[ char s ] literal emit '"' emit space ( print s"<space> )
			8 + dup @		( get the length word )
			swap 4 + swap		( end start+4 length )
			2dup tell		( print the string )
			'"' emit space		( finish the string with a final quote )
			+ aligned		( end start+4+len, aligned )
			8 -			( because we're about to add 4 below )
		endof
		' 0branch of		( is it 0branch ? )
			." 0branch ( "
			8 + dup @		( print the offset )
			.
			." ) "
		endof
		' branch of		( is it branch ? )
			." branch ( "
			8 + dup @		( print the offset )
			.
			." ) "
		endof
		' ' of			( is it ' (tick) ? )
			[ char ' ] literal emit space
			8 + dup @		( get the next codeword )
			cfa>			( and force it to be printed as a dictionary entry )
			id. space
		endof
		' exit of		( is it exit? )
			( we expect the last word to be exit, and if it is then we don't print it
			  because exit is normally implied by ;.  exit can also appear in the middle
			  of words, and then it needs to be printed. )
			2dup			( end start end start )
			8 +			( end start end start+4 )
			<> if			( end start | we're not at the end )
				." exit "
			then
		endof
					( default case: )
			dup			( in the default case we always need to dup before using )
			cfa>			( look up the codeword to get the dictionary entry )
			id. space		( and print it )
		endcase

		8 +		( end start+4 )
	repeat

	';' emit cr

	2drop		( restore stack )
;

(
	EXECUTION TOKENS ----------------------------------------------------------------------

	Standard FORTH defines a concept called an 'execution token' (or 'xt') which is very
	similar to a function pointer in C.  We map the execution token to a codeword address.

			execution token of DOUBLE is the address of this codeword
						    |
						    V
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
	| LINK    | 6 | D | O | U | B | L | E | 0 | DOCOL      | DUP        | +          | EXIT       |
	+---------+---+---+---+---+---+---+---+---+------------+------------+------------+------------+
                   len                         pad  codeword					       ^

	There is one assembler primitive for execution tokens, EXECUTE ( xt -- ), which runs them.

	You can make an execution token for an existing word the long way using >CFA,
	ie: WORD [foo] FIND >CFA will push the xt for foo onto the stack where foo is the
	next word in input.  So a very slow way to run DOUBLE might be:

		: DOUBLE DUP + ;
		: SLOW WORD FIND >CFA EXECUTE ;
		5 SLOW DOUBLE . CR	\ prints 10

	We also offer a simpler and faster way to get the execution token of any word FOO:

		['] FOO

	(Exercises for readers: (1) What is the difference between ['] FOO and ' FOO?
	(2) What is the relationship between ', ['] and LIT?)

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

	Notice that the above code has a memory leak: the anonymous word is still compiled
	into the data segment, so even if you lose track of the xt, the word continues to
	occupy memory.  A good way to keep track of the xt and thus avoid the memory leak is
	to assign it to a CONSTANT, VARIABLE or VALUE:

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

: :noname
	0 0 create	( create a word with no name - we need a dictionary header because ; expects it )
	here @		( current here value is the address of the codeword, ie. the xt )
	docol ,		( compile docol (the codeword) )
	]		( go into compile mode )
;

: ['] immediate
	' lit ,		( compile lit )
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

	The implementation hangs on the definitions of CATCH and THROW and the state shared
	between them.

	Up to this point, the return stack has consisted merely of a list of return addresses,
	with the top of the return stack being the return address where we will resume executing
	when the current word EXITs.  However CATCH will push a more complicated 'exception stack
	frame' on the return stack.  The exception stack frame records some things about the
	state of execution at the time that CATCH was called.

	When called, THROW walks up the return stack (the process is called 'unwinding') until
	it finds the exception stack frame.  It then uses the data in the exception stack frame
	to restore the state allowing execution to continue after the matching CATCH.  (If it
	unwinds the stack and doesn't find the exception stack frame then it prints a message
	and drops back to the prompt, which is also normal behaviour for so-called 'uncaught
	exceptions').

	This is what the exception stack frame looks like.  (As is conventional, the return stack
	is shown growing downwards from higher to lower memory addresses).

		+------------------------------+
		| return address from CATCH    |   Notice this is already on the
		|                              |   return stack when CATCH is called.
		+------------------------------+
		| original parameter stack     |
		| pointer                      |
		+------------------------------+  ^
		| exception stack marker       |  |
		| (EXCEPTION-MARKER)           |  |   Direction of stack
		+------------------------------+  |   unwinding by THROW.
						  |
						  |

	The EXCEPTION-MARKER marks the entry as being an exception stack frame rather than an
	ordinary return address, and it is this which THROW "notices" as it is unwinding the
	stack.  (If you want to implement more advanced exceptions such as TRY...WITH then
	you'll need to use a different value of marker if you want the old and new exception stack
	frame layouts to coexist).

	What happens if the executed word doesn't throw an exception?  It will eventually
	return and call EXCEPTION-MARKER, so EXCEPTION-MARKER had better do something sensible
	without us needing to modify EXIT.  This nicely gives us a suitable definition of
	EXCEPTION-MARKER, namely a function that just drops the stack frame and itself
	returns (thus "returning" from the original CATCH).

	One thing to take from this is that exceptions are a relatively lightweight mechanism
	in FORTH.
)

: exception-marker
	rdrop			( drop the original parameter stack pointer )
	0			( there was no exception, this is the normal return path )
;

: catch		( xt -- exn? )
	dsp@ 8+ >r		( save parameter stack pointer (+8 because of xt) on the return stack )
	' exception-marker 4+	( push the address of the rdrop inside exception-marker ... )
	>r			( ... on to the return stack so it acts like a return address )
	execute			( execute the nested function )
;

: throw		( n -- )
	?dup if			( only act if the exception code <> 0 )
		rsp@ 			( get return stack pointer )
		begin
			dup r0 8- <		( rsp < r0 )
		while
			dup @			( get the return stack entry )
			' exception-marker 8+ = if	( found the exception-marker on the return stack )
				8+			( skip the exception-marker on the return stack )
				rsp!			( restore the return stack pointer )

				( restore the parameter stack. )
				dup dup dup		( reserve some working space so the stack for this word
							  doesn't coincide with the part of the stack being restored )
				r>			( get the saved parameter stack pointer | n dsp )
				8-			( reserve space on the stack to store n )
				swap over		( dsp n dsp )
				!			( write n on the stack )
				dsp! exit		( restore the parameter stack pointer, immediately exit )
			then
			8+
		repeat

		( no matching catch - print a message and restart the interpreter. )
		drop

		case
		0 1- of	( abort )
			." aborted" cr
		endof
			( default case )
			." uncaught throw "
			dup . cr
		endcase
		quit
	then
;

: abort		( -- )
	0 1- throw
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

(
	C STRINGS ----------------------------------------------------------------------

	FORTH strings are represented by a start address and length kept on the stack or in memory.

	Most FORTHs don't handle C strings, but we need them in order to access the process arguments
	and environment left on the stack by the Linux kernel, and to make some system calls.

	Operation	Input		Output		FORTH word	Notes
	----------------------------------------------------------------------

	Create FORTH string		addr len	S" ..."

	Create C string			c-addr		Z" ..."

	C -> FORTH	c-addr		addr len	DUP STRLEN

	FORTH -> C	addr len	c-addr		CSTRING		Allocated in a temporary buffer, so
									should be consumed / copied immediately.
									FORTH string should not contain NULs.

	For example, DUP STRLEN TELL prints a C string.
)

(
	Z" .." is like S" ..." except that the string is terminated by an ASCII NUL character.

	To make it more like a C string, at runtime Z" just leaves the address of the string
	on the stack (not address & length as with S").  To implement this we need to add the
	extra NUL to the string and also a DROP instruction afterwards.  Apart from that the
	implementation just a modified S".
)
: z" immediate
	state @ if	( compiling? )
		' litstring ,	( compile litstring )
		here @		( save the address of the length word on the stack )
		0 ,		( dummy length - we don't know what it is yet )
		begin
			key 		( get next character of the string )
			dup '"' <>
		while
			here @ c!	( store the character in the compiled image )
			1 here +!	( increment here pointer by 1 byte )
		repeat
		0 here @ c!	( add the ascii nul byte )
		1 here +!
		drop		( drop the double quote character at the end )
		dup		( get the saved address of the length word )
		here @ swap -	( calculate the length )
		8-		( subtract 4 (because we measured from the start of the length word) )
		swap !		( and back-fill the length location )
		align		( round up to next multiple of 4 bytes for the remaining code )
		' drop ,	( compile drop (to drop the length) )
	else		( immediate mode )
		here @		( get the start address of the temporary space )
		begin
			key
			dup '"' <>
		while
			over c!		( save next character )
			1+		( increment address )
		repeat
		drop		( drop the final " character )
		0 swap c!	( store final ascii nul )
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

(
        The assembler from the original jonesforth.f is i386 specific and wouldn't work at all on ARM64

        -mtnygard, 2024-07-04

)

(
        Hardware interface ---------------------------------------------------------------------------

        Working with modern hardware involves some complexity that wasn't a concern back when FORTH
        was created. For example, modern hardware has memory-mapped I/O devices with registers that
        are a different size than the native cell size for the CPU. The ARM64 CPU uses 64-bit words
        so our cell size is 64 bits and most of our operations use the 64-bit registers. But that
        won't work when reading and writing device registers that are 32 bits. We defined `w!` and
        `w@` in assembly to help with that. It's helpful to have `w,` as well, but with one
        caveat. We store the 32-bit value in a 64-bit word so we don't have to worry about access
        alignment everywhere. It's a little bit of memory waste but a bit improvement in reliability.

)

( w, appends a 32-bit value to the current compiled word. )
: w,
	here @ w!	( store the character in the compiled image )
	1 cells here +!	( increment here pointer by 1 cell )
;

(

        Another concern that didn't exist when FORTH was created was caching. In our multicore and
        memory-mapped world, we have to do some manual cache maintenance when handing memory off
        between cores or devices. That means we need to be able to clean regions of the cache by
        writing modified contents to main memory or invalidate regions.

        --- this comment is a placeholder for when we figure out what these words should be ---

)



(
	NOTES ----------------------------------------------------------------------

	DOES> isn't possible to implement with this FORTH because we don't have a separate
	data pointer.
)

: noecho 0 echo ! ;
: echo 1 echo ! ;

(
	WELCOME MESSAGE ----------------------------------------------------------------------

	Print the version and OK prompt.
)

: welcome
        cr
	s" test-mode" find not if
		." jonesforth version " version . cr
		." ok "
	then
        cr
;

welcome
hide welcome
echo
