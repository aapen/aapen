\ -*- forth -*-
\
\ This is the initial boot code for AApen. This file defines everything up to the 'evaluate'
\ word (which includes the assembler).
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

: troff 0 echo ! ;
: tron  1 echo ! ;

: cells 8 * ;
: cell+ 1 cells + ;

: chars ;
: char+ 1 + ;

\ x y z -- y z x
:  rot >r swap r> swap ;

\ x y z -- z x y
: -rot swap >r swap r> ;

\ x y -- y
: nip  swap drop ;

\ x y -- y x y
: tuck swap over ;

\  x_u ... x_1 x_0 u -- x_u ... x_1 x_0 x_u
: pick 1 + cells dsp@ + @ ;

\ Standard words for booleans.
: true  -1 ;
: false 0 ;
: not   0= ;
: 0<>   0= not ;

\ We don't have `if` yet, and won't until after we have `postpone`. Instead we use this arithmetic
\ conditional to select a value

\ a b c -- (b&c)|(a&~c)
: ?:
  tuck                          \ a c b c
  and                           \ a c b&c
  -rot                          \ b&c a c
  not and                       \ b&c a&~c
  or                            \ (b&c)|(a&~c)
;

: count dup c@ >r 1 + r> ;

\ Append to the word being compiled. For Aapen, `compile,` is the same as `,`
: compile, , ;

\ Word flags are in byte 8 of the header
: flags 8 + c@ ;
: ?flag flags and 0<> ;
: ?hidden f_hidden swap ?flag ;
: ?immediate f_immed swap ?flag ;

\ The next three words are sensitive to the layout of the word header. See `armforth.S` for the
\ layout. We're going to use these to build up our execution machinery, so they have to appear
\ early. That also means we don't get a bunch of nice affordances that appear later, such as control
\ flow.

\ Word name is a counted string starting at +9 bytes
\ nt -- c-addr u
: name>string    9 + count ;

\ nt -- xt | 0  : xt refers to the interpretation semantics of the word. 0 results if it has no defined interpretation semantics
: name>interpret 40 + ;

\ nt -- xt1 xt2 : xt1 refers to the compilation semantics of the word, xt2 is the 'invoker' that will perform it
: name>compile
  dup name>interpret swap       \ xt1 nt         |  put the word's xt on stack
  ['] compile, ['] execute      \ xt1 nt xtc xte | compilation behavior is to execute, else to compile
  rot ?immediate                \ xt1 xtc xte ?i
  ?:
;

\ The 2... versions of the standard operators work on pairs of stack entries.
: 2dup over over ;
: 2drop drop drop ;
: 2swap rot >r rot r> ;
: 2@ dup 8+ @ swap @ ;
: 2! dup 8+ rot rot ! ! ;
: 2over 3 pick 3 pick ;         \ x y z w -- x y z w x y

\ Some common defining words.  In Aapen, a constant and a value behave
\ the same. Technically you could re-assign a new value to a constant,
\ but that would be bad form.

: constant create   , does> @ ;
: variable create 0 , does> ;
: value	   create   , does> @ ;

\ FORTH allows ( ... ) as comments within function definitions. This
\ works by having an immediate word called ( which asks the parser to
\ parse the input stream until ')' is found. Then we ignore everything
\ that we just parsed. This has the effect of dropping input
\ characters from the ( to the ). From now on we can use ( ... ) for
\ multiline comments.  Note that nested parens won't work.

0d41 constant ')'
: ( ')' parse 2drop ; immediate

(
  Ways to raise an exception. The magic numbers -1 and -2 are standard
  for 'abort without message' and 'abort with message'.
)

: abort	 ( -- ) -1 throw ;

0d34 constant '"'
: abort" ( "msg" -- ) '"' parse -2 throw ;


( Division and mod )

: /     /mod swap drop ;
: mod   /mod drop ;
: */    >r * r> / ;
: */mod >r * r> /mod ;

( Standard words for manipulating BASE. )

: decimal ( -- ) 10 base ! ;
: hex     ( -- ) 16 base ! ;
: binary  ( -- ) 2 base ! ;

( Define some character constants )

0d09 constant '\t'
0d10 constant '\n'
0d13 constant '\r'
0d27 constant 'esc'
0d32 constant bl

: tab '\t' emit ;
: cr '\n' emit ;
: space bl emit ;

( More standard FORTH words. )
( TBD define these in assembly later)

: 2* 2 * ;
: 2/ 2 / ;

( negate leaves the negative of a number on the stack. )

: negate 0 swap - ;


( `literal` takes whatever is on the stack and compiles `lit <foo>.` )
: literal ['] lit compile, compile, ; immediate

( Here we also define `lit,` which does the same thing as `literal` but is not
  immediate. )

: lit, ( x -- ) ['] lit compile, , ;

( while compiling, '[compile] word' compiles 'word' if it would otherwise be IMMEDIATE. )

: [compile]
	word		( get the next word )
	find		( find it in the dictionary )
	>cfa		( get its codeword )
	,		( and compile that )
; immediate

: (0skip) ['] 0branch , 8 , ; immediate
: @execute @ dup (0skip) execute ;

( DEFER and IS provide a convenient way to manage an execution
  vector. DEFER defines a word that can have its behavior replaced later by IS.

  For example:

  defer <name>
  <xt> IS <name>

  You'll find IS much later, since it requires "throw", which in turn requires "IF" and friends.
)

: defer ( "name" -- )
  create ['] abort ,            ( create word, default behavior is to abort )
  does> @execute                ( look up xt from data field, execute it )
;

( Here is the long-awaited definition of IS )

: is ( xt "name" -- ) word find dup 0= -13 and throw >dfa ! ;

: postpone ( compilation: "name" -- )
  state @ 0= -14 and throw                      ( ensure `postpone` only happens in compilation )
  word find dup 0= -13 and throw                ( waddr | locate word )
  name>compile swap lit, compile,               ( compile xt and "invoker" in current word )
; immediate

( recurse makes a recursive call to the current word that is being compiled.
 Normally while a word is being compiled, it is marked HIDDEN so that references to the
 same word are calls to the previous definition of the word.  However we still have
 access to the word which we are currently compiling through the LATEST pointer so we
 can use that to compile a recursive call. )

: recurse
  latest @                              ( latest points to the word being compiled at the moment )
  >cfa                                  ( get the codeword )
  ,		                        ( compile it )
; immediate

( Some more character constants )
: [char] word drop c@ lit, ; immediate

: ':' [char] : ;
: ';' [char] ; ;
: ')' [char] ) ;
: '<' [char] < ;
: '>' [char] > ;
: 'A' [char] A ;
: 'J' [char] J ;
: 'H' [char] H ;
: 'a' [char] a ;
: 'b' [char] b ;
: 'c' [char] c ;
: '0' [char] 0 ;
: '1' [char] 1 ;
: '2' [char] 2 ;
: '-' [char] - ;
: '.' [char] . ;
: '[' [char] [ ;

( Control structures.
 Note that the control structures will only work inside compiled words.

 `if`, `else`, and `then` are defined in armforth.S because we need
 them to implement `postpone`, and we then use `postpone` to define
 the others.

 condition IF true-part THEN rest
	-- compiles to: --> condition 0BRANCH OFFSET true-part rest
	where OFFSET is the offset of 'rest'
 condition IF true-part ELSE false-part THEN
 	-- compiles to: --> condition 0BRANCH OFFSET true-part BRANCH OFFSET2 false-part rest
	where OFFSET if the offset of false-part and OFFSET2 is the offset of rest

 IF is an IMMEDIATE word which compiles 0BRANCH followed by a dummy offset, and places
 the address of the 0BRANCH on the stack.  Later when we see THEN, we pop that address
 off the stack, calculate the offset, and back-fill the offset. )


: if
  postpone 0branch              ( compile 0branch )
  here                          ( save location of the offset on the stack )
  0 ,                           ( compile a dummy offset )
; immediate

: then
  dup
  here swap -                   ( calculate offset from the addr saved on the stack )
  swap !                        ( store the offset in the back-filled location )
; immediate

: else
  postpone branch               ( definite branch to just over the false-part )
  here                          ( save location of the offset on the stack )
  0 ,                           ( compile a dummy offset )
  swap                          ( now back-fill the original if offset )
  dup                           ( same as for then word above )
  here swap -
  swap !
; immediate

( ahead skipped-code then
  -- compiles to: --> branch offset skipped-code )

: ahead
  postpone branch
  here 0 ,
; immediate

( begin loop-part condition until
  -- compiles to: --> loop-part condition 0branch offset
   where offset points back to the loop-part
 This is like do { loop-part } while condition in the C language. )

: begin
  here                                  ( save location on the stack )
; immediate

: until
  postpone 0branch                      ( compile 0branch )
  here -                                ( calculate the offset from the address saved on the stack )
  ,                                     ( compile the offset here )
; immediate

( begin loop-part again
	-- compiles to: --> loop-part branch offset
	where offset points back to the loop-part
 In other words, an infinite loop which can only be returned from with EXIT )

: again
  postpone branch                       ( compile branch )
  here -                                ( calculate the offset back )
  ,                                     ( compile the offset here )
; immediate

( begin condition while loop-part repeat
	-- compiles to: --> condition 0branch offset2 loop-part branch offset
	where offset points back to condition--the beginning--and offset2
	points to after the whole piece of code
        So this is like a while condition { loop-part } loop in the C language.)

: while
  postpone 0branch                      ( compile 0branch )
  here                                  ( save location of the offset2 on the stack )
  0 ,                                   ( compile a dummy offset2 )
; immediate

: repeat
  postpone branch                       ( compile branch )
  swap                                  ( get the original offset from begin)
  here - ,                              ( and compile it after branch )
  dup
  here swap -                           ( calculate the offset2 )
  swap !                                ( and back-fill it in the original location )
; immediate

( unless is the same as if but the test is reversed. )

: unless
  postpone not                  ( compile not to reverse the test )
  postpone if                   ( continue by calling the normal if )
; immediate

\ transfer N items and count to return stack
: n>r ( xn .. x1 n -- ;  r: -- x1 .. xn n )
  dup
  begin
    dup
  while
    rot r> swap >r >r
    1 -
  repeat
  drop
  r> swap >r >r
;

\ pull N items and count off the return stack
: nr> ( -- xn .. x1 n ; r: x1 .. xn n -- )
  r> r> swap >r dup
  begin
    dup
  while
    r> r> swap >r -rot
    1 -
  repeat
  drop
;

\ `do` is similar to `begin`, but it has some extra runtime behavior to take the start, limit, and
\ step from the stack and tuck them away on the rstack. We call the extra tracking info the
\ 'loop-sys'. Inside the loop body we access the loop-sys to update the index and check for loop
\ exit.
\
\ It's important that we remove the loop-sys from the rstack before we attempt to leave the word
\ that invoked the loop... otherwise we'll try to 'return' to some integer that was the loop
\ index. The _best case_ then would be an alignment fault. The worst case would be that we actually
\ execute some undefined chunk of memory.
\
\ do loop-body loop
\	-- compiles to: --> setup loop-body 1 (loop-inc) (loop-done?) 0branch offset
\ where offset points back to just before the loop-body

\ Push loop-sys onto return stack
: (>loop-sys) ( limit index -- )
  r>          ( limit index real-return )
  swap >r     ( limit real-return )
  swap >r     ( real-return )
  >r
;

\ Peek at loop-sys from return stack
: (loop-sys-peek) ( -- limit index )
  rsp@ 8+ @
  rsp@ 16 + @
;

\ Pop loop-sys from return stack, push it to parameter stack
: (loop-sys>)  ( -- limit index )
  r>           ( real-return )
  r> swap      ( limit real-return )
  r> swap      ( limit index real-return )
  >r           ( limit index )
;

: do ( lim curr -- )
  0
  postpone (>loop-sys)
  here 
; immediate

\ `?do` is like `do`, but skips the loop body entirely if the limit and index are equal.
\ In other words you can use this when it's possible for the loop body to be
\ executed zero times.
\
\ ?do loop-body loop
\	-- compiles to: -->
\  bounds<>? 0branch offset2 setup loop-body (loop-inc) (loop-done?) 0branch offset1
\ where offset2 points just after the final 0branch and lets us skip the whole thing
\ and offset1 points back to just before the loop-body
\
\ Note that we unconditionally put the limit and count onto rstack so the
\ +loop can drop them later.

: ?do
  postpone 2dup
  postpone (>loop-sys)
  postpone = postpone not               ( compile execution-time test on bounds )
  postpone 0branch                      ( if bounds equal, we will skip the body )
  here                                  ( remember where to fill in the offset )
  0 ,                                   ( dummy placeholder to fix up later )
  1                                     ( remember on the stack this was a qdo )
  here                                  ( save location that will be the loop target )
; immediate

\ Whatever word invoked the loop can't use `exit` as long as the loop-sys is still on
\ rstack. `unloop` cleans up the rstack so `exit` won't cause a problem.
: unloop
  r>                            ( keep actual return addr )
  (loop-sys>) 2drop             ( drop the loop-sys )
  >r                            ( restore actual return addr )
;

\ There are two words to end the loop's body: `loop` and `+loop`.
\ The first one increments the loop counter by 1. The second increments it by
\ some number. We will start with the general case, then define the simple case
\ as a usage of the general one.
\
\ Since there's quite a bit of rstack manipulation needed, we define some helper words.
\ None of these change the rstack, they just access or manipulate the loop control
\ structure in place.
\
\ Given the way we defined the loop control structure, you'd expect to find `i` at RSP+8.
\ That's true, except that we had to call `i` itself, which puts another address on
\ the rstack. Confusing? Yes. It also means that we can't use `i` except _directly_
\ inside a do..loop. No calling it from another word or the offsets will be
\ wrong. Same goes for `j`

: i rsp@ 16 + @ ;               ( get current loop count )
: j rsp@ 32 + @ ;               ( get outer loop count )

: signs-differ? ( a b -- f )
  xor [ 1 63 lshift ] literal and 0<>
;

: (loop-done?) ( step limit index -- f )
  2dup = if 2drop drop true exit then      ( early out if numbers are equal )
  swap                                     ( step index limit )
  -                                        ( step index-limit )
  dup                                      ( step index-limit index-limit )
  -rot                                     ( index-limit step index-limit )
  +                                        ( index-limit index-limit+step )
  signs-differ?
;

: (loop-inc) ( step -- )
  r>
  (loop-sys>) ( step limit index )
  3 pick      ( limit index step )
  +           ( limit index' )
  (>loop-sys) ( )
  >r
  drop
;


\ `+loop` is a bit of a beast. It needs to compile the runtime code to update
\ the loop count and check it against the limit. It also needs to recall if the loop was started
\ with a `?do` so it can backpatch the jump-ahead target

: +loop ( step )
  postpone dup                 ( step step )
  postpone (loop-sys-peek)     ( step step limit index )
  postpone (loop-done?)        ( step done )
  postpone swap                ( done step )
  postpone (loop-inc)          ( done )
  postpone 0branch             ( return to head of loop )
  here - ,                     ( compile addr of loop head ... was left on pstack by `do` )
  if                           ( was this a qdo? )
    here over - swap !         ( backpatch qdo's 0branch target )
  then
  postpone unloop
; immediate

( And here's the special case to just step by 1. )

: loop
  1 lit,
  postpone +loop
; immediate

( Leaves the max of two numbers on the stack. )
: max 2dup < if swap then drop ;

( With the looping constructs, we can now write SPACES, which writes n spaces to stdout. )

: spaces ( n -- ) 0 max 0 ?do space loop ;
: zeroes ( n -- ) 0 max 0 ?do '0' emit loop ;

( allot allocates n bytes of memory.  Note when calling this that
 it's a very good idea to make sure that n is a multiple of 8, or
 at least that next time a word is compiled that HERE has been
 aligned. )

: allot	( n -- ) &here +! ;


( aligned takes an address and rounds it up to the next 8 byte boundary.)

: aligned-to ( addr n -- addr ) 1 - dup >r + r> invert and ;
: aligned ( addr -- addr ) 1 cells aligned-to ;

( ALIGN aligns the HERE pointer, so the next word appended will be aligned properly.)
: align    ( -- )   here aligned here - allot ;
: align-to ( n -- ) here swap aligned-to here - allot ;

( compile a string into the current compiled word. )

: s, ( c-addr u -- )
  2dup here swap cmove allot drop
;

( s" string" is used in FORTH to define strings.  It leaves the address of the
  string and its length on the stack, with length at the top of stack.  The space
  following S" is the normal space between FORTH words and is not a part of the string.

  s" is tricky to define because it has to do different things depending on whether
  we are compiling or in immediate mode.  Thus the word is marked IMMEDIATE so it can
  detect this and do different things.

  In compile mode we append LITSTRING <string length> <string rounded up 4 bytes>
  to the current word.  The primitive LITSTRING does the right thing when the current
  word is executed.

  In immediate mode there isn't a particularly good place to put the string, but in this
  case we put the string at HERE  -- but we _don't_ change HERE.
  This is meant as a temporary location, likely to be overwritten soon after.
)

: s"   ( c: "ccc<quote>" -- ; r: -- c-addr u )
  state @ if                    ( compiling? )
    postpone litstring          ( compile litstring )
    here                        ( save the address of the length word on the stack )
    0 ,                         (  dummy length - we don't know what it is yet )
    '"' parse s,
    dup		                ( get the saved address of the length word )
    here swap -                 ( calculate the length )
    8 -                         ( subtract 8 because we measured from the start of the length word )
    swap !                      ( and back-fill the length location )
    align		        ( round up to next multiple of 4 bytes for the remaining code )
  else                          ( immediate mode )
    '"' parse 2dup here swap cmove
    nip here swap
  then
; immediate

( ." is the print string operator in FORTH.  Example: ." Something to print"
  The space after the operator is the ordinary space required between words and is not
  a part of what is printed.

  In immediate mode we just keep reading characters and printing them until we get to
  the next double quote.

  In compile mode we use S" to store the string, then add TYPE afterwards:
  LITSTRING <string length> <string rounded up to 4 bytes> TYPE
)

: ." ( "ccc<quote>" -- )
  state @ if                    ( compiling? )
    postpone s"                 ( read the string, and compile litstring, etc. )
    postpone type               ( compile the final type )
  else
    '"' parse type
  then
; immediate

( w, appends a 32-bit value to the current compiled word. )

: w,
  here w!                        ( store the character in the compiled image )
  4 allot
;

( ASSEMBLER HERE )


( ARM assembler )

( Utility words that set fields on the instructions. )
: set-rt ( instruction rt - instruction )
  or
;


: set-ra ( instruction ra -- instruction )
  0b11111 and
  0d10 lshift
  or
;

: set-rn ( instruction rn -- instruction )
  0b11111 and
  0d5 lshift
  or
;

: set-rm ( instruction rm -- instruction )
  0b11111 and
  0d16 lshift
  or
;

: set-im21-hi ( instruction im21 -- instruction )
  0d2 rshift 0d5 lshift       ( instruction im21-hibits )
  or
;

: set-im21-low ( instruction im21 -- instruction )
  0d3 and 0d29 lshift		( instruction im21-lowbits )
  or
;

: set-im26 ( instruction im26 -- instruction )
  0x3ffffff and			( instruction im26 )
  or
;

: set-im21 ( instruction im21 -- instruction )
  dup rot rot			( im21 instruction im21 )
  set-im21-hi			( im21 instruction )
  swap set-im21-low             ( instruction )
;

: set-im19 ( instruction im19 -- instruction )
  0b1111111111111111111 and	( instruction im19 )
  0d5 lshift                   ( instruction mask )
  or
;

: set-im16 ( instruction im16 -- instruction )
  0b1111111111111111 and	( instruction im16 )
  0d5 lshift                   ( instruction mask )
  or
;

: set-im12 ( instruction im12 -- instruction )
  0b111111111111 and		( instruction im12 )
  0d10 lshift                  ( instruction mask )
  or
;

: set-im9 ( instruction im9 -- instruction )
  0b111111111 and		( instruction im9 )
  0d12 lshift                  ( instruction mask )
  or
;

: set-im6 ( instruction im6 -- instruction )
  0b111111 and			( instruction im6 )
  0d10 lshift                  ( instruction mask )
  or
;

: rt-rn-rm-ra-instruction ( rt rn rm ra opcode -- instruction )
  swap set-ra			( rt rn rm instuction )
  swap set-rm			( rt rn instuction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-rm-instruction ( rt rn rm opcode -- instruction )
  swap set-rm			( rt rn instuction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rn-rm-im6-instruction ( rn rm im6 opcode -- instruction )
  swap set-im6
  swap set-rm
  swap set-rn
;

: rt-rn-im9-instruction ( rt rn im9 opcode -- instruction )
  swap set-im9			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-im12-instruction ( rt rn im12 opcode -- instruction )
  swap set-im12			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rt-rn-im19-instruction ( rt rn im19 opcode -- instruction )
  swap set-im19			( rt rn instruction )
  swap set-rn			( rt instuction )
  swap set-rt			( instruction )
;

: rn-instruction ( rn opcode -- instruction )
  swap set-rn			( rn instuction )
;

: rt-rn-instruction ( rt rn opcode -- instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: im16-instruction ( im16 opcode -- instruction )
  swap set-im16
;

: rt-im16-instruction ( rt im16 opcode -- instruction )
  swap set-im16
  swap set-rt
;

: rt-im19-instruction ( rt im19 opcode -- instruction )
  swap set-im19			( rt instruction )
  swap set-rt
;

: rt-im21-instruction ( rt im21 opcode -- instruction )
  swap set-im21			( rt instruction )
  swap set-rt
;

( Condition codes used by the b-cond instruction )

: c-eq 0b0000 ;
: c-ne 0b0001 ;
: c-cs 0b0010 ;
: c-cc 0b0011 ;
: c-mi 0b0100 ;
: c-pl 0b0101 ;
: c-vs 0b0110 ;
: c-vc 0b0111 ;
: c-hi 0b1000 ;
: c-ls 0b1001 ;
: c-ge 0b1010 ;
: c-lt 0b1011 ;
: c-gt 0b1100 ;
: c-le 0b1101 ;
: c-al 0b1110 ;
: c-nv 0b1111 ;

( Instruction modifiers )

( Turn instruction into the 32 bit version of itself )

: ->w ( instruction -- instruction )
  0x7fffffff and	( clear bit 31 )
;

( Turn on the shift option )

: ->shift ( instruction -- instruction )
  1 0d22 lshift
  or
;

( Set the condition code for a b-cond instruction )

: ->cond ( instruction cond -- instruction )
  0b1111 and
  or
;

( Set the preindex option )

: ->pre ( instruction -- instruction )
  0b11 0d10 lshift
  or
;

( Set the postindex option )

: ->post ( instruction -- instruction )
  0b01 0d10 lshift
  or
;

( These are the actual assembler instructions. )

0d31 constant zr

( Load and store )

( Note the immediate offsets are multiplied by 8 when executed )

: ldr-x[x]#  ( rt rn im12 -- instruction )  0xf8400000 rt-rn-im9-instruction ->post ;
: ldr-x[x]   ( rt rn      -- instruction )  0 0xf8400000 rt-rn-im9-instruction ;

: ldr-x[x#]! ( rt rn im12 -- instruction )  0xf8400000 rt-rn-im9-instruction ->pre ;
: ldr-x#     ( rt im19 -- instruction )     58000000 rt-im19-instruction ;

: ldrb-w[x]# ( rt rn im9 -- instruction ) 0x38400000 rt-rn-im9-instruction ->post ;
: ldrb-w[x]  ( rt rn     -- instruction ) 0 0x39400000 rt-rn-im12-instruction ;
: ldrb-w[x#] ( rt rn im12 -- instruction ) 0x39400000 rt-rn-im12-instruction ;
: ldr-x[x#]  ( rt rn im12 -- instruction )  0xf9400000 rt-rn-im12-instruction ;

: str-x[x#]! ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ->pre ;
: str-x[x#]  ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ;
: str-x[x]#  ( rt rn im12 -- instruction ) 0xf8000000 rt-rn-im9-instruction ->post ;
: str-x[x]  ( rt rn      -- instruction )  0xf9000000 rt-rn-instruction ;

: str-w[x]  ( rt rn      -- instruction )  0xb9000000 rt-rn-instruction ;

: strb-w[x#]  ( rt rn im12 -- instruction ) 0x39000000 rt-rn-im12-instruction ;
: strb-w[x]   ( rt rn im12 -- instruction ) 0 strb-w[x#] ;
: strb-w[x]#  ( rt rn im12 -- instruction ) 0x38000000 rt-rn-im9-instruction ->post ;

( Address arithmetic )

: adr-x# ( rt relative ) 0x10000000 rt-im21-instruction ;


( Bits and Arithmetic )

: orr-xxx ( rt rn rm -- instruction ) 0xaa000000 rt-rn-rm-instruction ;
: orr-www ( rt rn rm -- instruction ) orr-xxx ->w ;

: eor-xxx ( rt rn rm -- instruction  )
  0xca000000 rt-rn-rm-instruction
;

: mvn-xx  ( rt rm -- instruction  )
    0x1f swap
    0xaa200000
    rt-rn-rm-instruction
;

: and-xxx ( rt rm rn -- instruction  )
    0x8a000000 rt-rn-rm-instruction
;

: add-xx# ( rt rn im12 -- instruction ) 0x91000000 rt-rn-im12-instruction ;
: add-xxx ( rt rm rn -- instruction )   0x8b000000 rt-rn-rm-instruction ;
: add-ww# ( rt rn im12 -- instruction ) add-xx# ->w ;
: add-www ( rt rm rn -- instruction )  add-xxx ->w ;

: sub-xx# ( rt rn im12 -- instruction ) 0xd1000000 rt-rn-im12-instruction ;
: sub-xxx ( rt rm rn -- instruction )   0xcb000000 rt-rn-rm-instruction ;
: sub-ww# ( rt rn im12 -- instruction ) sub-xx# ->w ;
: sub-www ( rt rm rn -- instruction )  sub-xxx ->w ;

: subs-xxx ( rt rn rm   -- instruction ) 0xeb200000 rt-rn-rm-instruction ;
: subs-xx# ( rt rn im12 -- instruction ) 0xf1000000 rt-rn-im12-instruction ;
: subs-ww# ( rt rn im12 -- instruction ) subs-xx# ->w ;

: cmp-x#  ( rn im12 -- instruction ) 0x1f rot rot subs-xx# ;
: cmp-w#  ( rt im12 -- instruction ) cmp-x# ->w ;

: cmp-xx  ( rm rn -- instruction  )
  0
  0xeb000000
  rn-rm-im6-instruction
;

: madd-xxxx ( rt rm rn ra -- instruction ) 0x9b000000 rt-rn-rm-ra-instruction ;
: msub-xxxx ( rt rm rn ra -- instruction ) 0x1b008000 rt-rn-rm-ra-instruction ;
: mul-xxx ( rt rm rn -- instruction )   0x1f 0x9b000000 rt-rn-rm-ra-instruction ;
: mul-www ( rt rm rn -- instruction ) mul-xxx ->w ;

: sdiv-xxx ( rt rn rm -- instruction ) 0x9ac00c00 rt-rn-rm-instruction ;

: udiv-xxx ( rt rn rm -- instruction ) 0x9ac00800 rt-rn-rm-instruction ;
: umsubl-xxxx ( rt rm rn ra -- instruction ) 0x9b008000 rt-rn-rm-ra-instruction ;

( Shifting  )

: lsl-xxx ( rt rm rn -- instruction  )
  0x9ac02000 rt-rn-rm-instruction
;

: lsr-xxx ( rt rm rn -- instruction  )
  0x9ac02400 rt-rn-rm-instruction
;

( Move )

: mov-xx ( rt rm -- instruction ) 0d31 swap orr-xxx ;
: mov-ww ( rt rm -- instruction ) 0d31 swap orr-www ;

: mov-x# ( rt im16 -- instruction) 0xd2800000 rt-im16-instruction ;
: mov-w# ( rt im16 -- instruction) 0xd2800000 rt-im16-instruction ->w ;

: movn-x# ( rt im16 -- instruction) 0x92800000 rt-im16-instruction ;

( Branches )

: cbz-x#  ( rt im19 -- instruction ) 0xb4000000 rt-im19-instruction ;
: cbnz-x# ( rt im19 -- instruction ) 0xb5000000 rt-im19-instruction ;
: svc-#   ( im16 -- instruction )    0xd4000001 im16-instruction ;
: hlt-# ( im16 -- instruction )      0xd4400000 im16-instruction ;

: ret-x ( rn -- instruction )  0xd65f0000 swap set-rn ;
: ret- ( -- instruction )      0d30 ret-x ;
: br-x ( rn -- instruction )   0xd61f0000 rn-instruction ;
: b-# ( im26 -- instruction )  0x14000000 swap set-im26 ;
: bl-# ( im26 -- instruction ) 0x94000000 swap set-im26 ;
: blr-x ( rn -- instruction )  0xd63f0000 rn-instruction ;


 ( Conditional branches. The fundimental instruction is b-cond + an
 instruction code. We predefine a few of the common cases.
 Keep in mind that the jump is relative and multiplied by 4. )

: b-cond ( im19 cond -- instruction )
  0x54000000			( im19 cond instruction )
  swap ->cond			( im19 instruction )
  swap set-im19
;

: beq-# ( im19 -- instruction ) c-eq b-cond ;
: bne-# ( im19 -- instruction ) c-ne b-cond ;
: blt-# ( im19 -- instruction ) c-lt b-cond ;
: bgt-# ( im19 -- instruction ) c-gt b-cond ;
: ble-# ( im19 -- instruction ) c-le b-cond ;
: bge-# ( im19 -- instruction ) c-ge b-cond ;
: bcs-# ( im19 -- instruction ) c-cs b-cond ;
: bcc-# ( im19 -- instruction ) c-cc b-cond ;

: csop-xxxc ( rt rn rm cond opcode -- instruction )
  rot        ( rt rn cond opcode rm  )
  set-rm     ( rt rn cond opcode  )
  rot        ( rt cond opcode rn  )
  set-rn     ( rt cond opcode  )
  rot        ( cond rt opcode  )
  set-rt     ( cond opcode  )
  swap       ( opcode cond  )
  0b1111 and
  0d12 lshift or
;

: csinc-xxxc ( rt rn rm cond-- instruction ) 0x9a800400 csop-xxxc ;
: csel-xxxc  ( rt rn rm cond -- instruction ) 0x9a800000 csop-xxxc ;
: csneg-xxxc ( rd rn rm cond -- instruction ) 0xda800400 csop-xxxc ;
: cset-xc    ( rt cond -- instruction ) zr swap zr swap csinc-xxxc ;
: cneg-xxc   ( rd rn cond -- instruction ) over swap csneg-xxxc ;

( System register instructions )

: sysreg 5 lshift constant ;

( See ARMARM Section D19 for system register encoding )
( bit order here is op0 op1 CRn CRm op2 )
0b1101111100000000 sysreg CNTFRQ_EL0
0b1101111100010001 sysreg CNTP_CTL_EL0
0b1101111100011001 sysreg CNTV_CTL_EL0
0b1101111100010000 sysreg CNTP_TVAL_EL0
0b1101111100011000 sysreg CNTV_TVAL_EL0
0b1101111100000010 sysreg CNTVCT_EL0
0b1100000010000000 sysreg SCTLR_EL1
0b1100011000000000 sysreg VBAR_EL1

: rt-sysreg-instruction swap set-rt or ;

: mrs-xr ( sysreg rt -- instruction ) 0xd5300000 rt-sysreg-instruction ;
: msr-rx ( rt sysreg -- instruction ) 0xd5100000 rt-sysreg-instruction ;

( Macros to push and pop a register from the data and returns stacks. )

0d28 constant psp
0d29 constant rsp

: pushrsp-x ( r -- instruction ) rsp -8 str-x[x#]! ;
: poprsp-x  ( r -- instruction ) rsp  8 ldr-x[x]# ;

: pushpsp-x ( r -- instruction ) psp -8 str-x[x#]! ;
: poppsp-x  ( r -- instruction ) psp  8 ldr-x[x]# ;

( Backward labels and address words )

variable loc-1b
variable loc-2b
variable loc-3b
variable loc-4b
variable loc-5b

: 1b: here loc-1b ! ;
: 2b: here loc-2b ! ;
: 3b: here loc-3b ! ;
: 4b: here loc-4b ! ;
: 5b: here loc-5b ! ;

: ->1b loc-1b @ here - 4 /  ;
: ->2b loc-3b @ here - 4 /  ;
: ->3b loc-3b @ here - 4 /  ;
: ->4b loc-4b @ here - 4 /  ;
: ->5b loc-5b @ here - 4 /  ;


( Forward labels and address words )

variable loc-1f
variable loc-2f
variable loc-3f
variable loc-4f
variable loc-5f

: ->1f here loc-1f ! 0 ;
: ->2f here loc-2f ! 0 ;
: ->3f here loc-3f ! 0 ;
: ->4f here loc-4f ! 0 ;
: ->5f here loc-5f ! 0 ;

: word-offset ( addr1 addr2 -- word-offset )
  - 4 /
;

( Given a branch instruction and an offset, update
the instruction to jump to that offset. This word deals
with the two forms of relative jumps. )

: patch-jump-offset ( offset instruction -- instruction )
  dup 0xff000000 and
  0x14000000 = if
    swap set-im26
  else
    swap set-im19
  then
;

( Given the addr of a branch instruction to patch, patch the
  immediate offset with the difference between the instruction
  address and here. )

: patch-jump-forward  ( address of instruction to patch -- )
  dup not if          ( check for undefined jump )
    ." Forward jump not defined!"
    exit
  then
  here over           ( ins-addr here ins-addr  )
  word-offset         ( ins-addr offset )
  over                ( ins-addr offset ins-addr )
  w@                  ( ins-addr offset instruction-to-be-patched )
  patch-jump-offset   ( ins-addr patched-instruction )
  swap w!
;

: 1f: loc-1f @ patch-jump-forward loc-1f 0 ! ;
: 2f: loc-2f @ patch-jump-forward loc-2f 0 ! ;
: 3f: loc-3f @ patch-jump-forward loc-3f 0 ! ;
: 4f: loc-4f @ patch-jump-forward loc-4f 0 ! ;
: 5f: loc-5f @ patch-jump-forward loc-5f 0 ! ;

: clear-jump-addresses ( -- )
  0 loc-1b !
  0 loc-2b !
  0 loc-3b !
  0 loc-4b !
  0 loc-5b !
  0 loc-1f !
  0 loc-2f !
  0 loc-3f !
  0 loc-4f !
  0 loc-5f !
;

( Create a new primitive word and leave its definition
  open. You *must* complete the word with ;; or it will
  surly crash. )

: defprim
  create                 ( Create a new word )
  here dup 8 - !         ( Put DFA into CFA )
;

( Close out an open primitive word. This is essentially
  the code for next in the assembly. )

: ;;
  0 0xa 8 ldr-x[x]# w,
  1 0   ldr-x[x]    w,
  1     br-x        w,
  align			( Next word aligns )
  clear-jump-addresses  ( Prevent cross word jumps )
;


( Test out the assembler )

( Define a noop primitive. )

defprim do-nothing
;;

defprim clear-stack
;;

defprim >body
  0     poppsp-x  w,
  0 0 8 add-xx#   w,
  0     pushpsp-x w,
;;

defprim 1+
  0     poppsp-x w,
  0 0 1	add-xx# w,
  0    	pushpsp-x w,
;;

defprim 1-
  0 		poppsp-x w,
  0 0 1 	sub-xx# w,
  0 		pushpsp-x w,
;;

defprim 4+
  0 		poppsp-x w,
  0 0 4 	add-xx# w,
  0 		pushpsp-x w,
;;

defprim 4-
  0 		poppsp-x w,
  0 0 4 	sub-xx# w,
  0 		pushpsp-x w,
;;

defprim lshift
  0 		poppsp-x w,
  1 		poppsp-x w,
  1 1 0 	lsl-xxx w,
  1 		pushpsp-x w,
;;

defprim rshift
  0 		poppsp-x w,
  1 		poppsp-x w,
  1 1 0 	lsr-xxx w,
  1 		pushpsp-x w,
;;

defprim >=
  1 		poppsp-x w,
  0 		poppsp-x w,
  2 0           mov-x# w,
  0 1 		cmp-xx w,
  ->1f          blt-#   w,
  2 2 1         sub-xx# w,
1f:
  2 		pushpsp-x w,
;;

defprim 0<
  0 		poppsp-x w,
  1 0           mov-x# w,
  0 zr 		cmp-xx w,
  ->1f          bge-#  w,
  1 1 1         sub-xx# w,
1f:
  1 		pushpsp-x w,
;;

defprim 0>
  0 		poppsp-x w,
  1 0           mov-x# w,
  0 zr 		cmp-xx w,
  ->1f          ble-# w,
  1 1 1         sub-xx# w,
1f:
  1 		pushpsp-x w,
;;

defprim 0>=
  0 		poppsp-x w,
  1 0           mov-x# w,
  0 zr 		cmp-xx w,
  ->1f          blt-# w,
  1 1 1         sub-xx# w,
1f:
  1 		pushpsp-x w,
;;

defprim u<
  0             poppsp-x  w,
  1             poppsp-x  w,
  1 0           cmp-xx    w,
  ->1f          bcs-#     w,
  0 0           movn-x#   w,
  ->2f          b-#       w,
1f:
  0 zr          mov-xx    w,
2f:
  0             pushpsp-x w,
;;

defprim u>
  0             poppsp-x  w,
  1             poppsp-x  w,
  0 1           cmp-xx    w,
  ->1f          bcs-#     w,
  0 0           movn-x#   w,
  ->2f          b-#       w,
1f:
  0 zr          mov-xx    w,
2f:
  0             pushpsp-x w,
;;

defprim -!
  0 		poppsp-x w,
  1 		poppsp-x w,
  2 0 		ldr-x[x] w,
  2 2 1 	sub-xxx w,
  2 0 		str-x[x] w,
;;

defprim um/mod
  2 		poppsp-x  w, \ x2 <- b
  1 		poppsp-x  w, \ x1 <- a
  0 1 2         udiv-xxx  w, \ x0 <- a/b
  3 0 2 1       msub-xxxx w, \ x3 <- a - (x0 * b)
  3             pushpsp-x w, \ push remainder
  0             pushpsp-x w, \ push quotient
;;

defprim c@c!
  0 28 8 	ldr-x[x#] w,
  1 28 		ldr-x[x] w,
  2 0 1 	ldrb-w[x]# w,
  2 1 1 	strb-w[x]# w,
  0 28 8 	str-x[x#] w,
  1 28 		str-x[x] w,
;;

( c-addr1 u1 c-addr2 u2 -- n )
defprim compare
	0	poppsp-x   w,
	1	poppsp-x   w,
	2	poppsp-x   w,
	3	poppsp-x   w,
        4 0	mov-x#     w,
1b:
        2 0     cmp-x#     w,
 2 0 2 c-eq     csel-xxxc  w,
        0 0     cmp-x#     w,
 0 2 0 c-eq     csel-xxxc  w,
     0 ->3f     cbz-x#     w,
      5 3 1     ldrb-w[x]# w,
      6 1 1     ldrb-w[x]# w,
      7 5 6     subs-xxx   w,
       ->2f     bne-#      w,
      2 2 1     sub-xx#    w,
      0 0 1     sub-xx#    w,
       ->1b     b-#        w,
2f:
        1 1     mov-x#     w,
        2 0     mov-x#     w,
      2 2 1     sub-xx#    w,
4 zr 1 c-gt     csel-xxxc  w,
 4 4 2 c-lt     csel-xxxc  w,
3f:
          4     pushpsp-x  w,
;;

(
defprim fence
  st 		dmb-st w,
;;

defprim dcc
  0 		poppsp-x w,
  cvac 0	dc-cvacx w,
;;

defprim dci
  0 		poppsp-x w,
  ivac 0 	dc-ivacx w,
;;

defprim dcci
  0 		poppsp-x w,
  civac 0 	dc-civacx w,
;;
)

( END ASSEMBLER )

( Building up to the key word . It takes the number at the top
  of the stack and prints it out. First I'm going to implement some lower-level FORTH words:
	u.r	 u width -- 	which prints an unsigned number, space-padded to a width
        u.r0     u width --     which prints an unsigned number, zero-padded to a  width
	u.             u -- 	which prints an unsigned number
	.r	 n width -- 	which prints a signed number, space-padded to a width.
)

: u.		( u -- )
	base @ um/mod	( width rem quot )
	?dup if			( if quotient <> 0 then )
		recurse		( print the quotient )
	then

	( print the remainder )
	dup 0d10 u< if
		'0'		( decimal digits 0..9 )
	else
		0d10 -		( hex and beyond digits a..z )
		'a'
	then
	+
	emit
;


( This word returns the width -- in char -- of an unsigned number in the current base )

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
	spaces
	u.
;

( TODO: refactor duplication in u.r, u.r0 and %02x, %08x )

: u.r0 swap dup uwidth rot swap - zeroes u. ;
: %02x base @ swap hex 2 u.r0 base ! ;
: %04x base @ swap hex 4 u.r0 base ! ;
: %08x base @ swap hex 8 u.r0 base ! ;
: %016x base @ swap hex 16 u.r0 base ! ;

( .R prints a signed number, padded to a certain width.  We can't just print the sign
  and call U.R because we want the sign to be next to the number, so
  '-123' instead of '-  123'.)

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

: xt word find >cfa ;

: begin-structure ( c: "<spaces>name" -- 0 )
  create
  here 0 0 ,
  does> ( r: -- size ) @
;

: +field ( n1 n2 <name> -- n3 )
  create over , +
  does> ( addr1 -- addr2 ) @ +
;

: cfield: 1 chars +field ;
: hfield: 2 chars aligned-to 2 chars +field ;
: wfield: 4 chars aligned-to 4 chars +field ;
: field: aligned 1 cells +field ;

: end-structure swap ! ;

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

( .x print the tos in hex )

: .x ( x -- )
	base @ 			( cur-base x )
	swap			( x cur-base )
	hex
	. 			( print x )
	base !			( restore the old base)
;

( .b print the tos in binary )

: .b ( x -- )
	base @ 			( cur-base x )
	swap			( x cur-base )
	binary
	. 			( print x )
	base !			( restore the old base)
;

( .d print the tos in decimal )

: .d ( x -- )
	base @ 			( cur-base x )
	swap			( x cur-base )
	decimal
	. 			( print x )
	base !			( restore the old base)
;

( ? fetches the integer at an address and prints it. )

: ? ( addr -- ) @ . ;
: ?x ( addr -- ) @ .x ;

( .base prints the current base in decimal )

: .base ( -- )
	base @ .d
;

( depth returns the depth of the stack. )

: depth		( -- n )
	s0 @ dsp@ -
	8-			( adjust because S0 was on the stack when we pushed DSP )
	8 /
;

( clear the data stack )

: clear-stack   ( <whatever> -- <empty> )
        s0 @ dsp!
;

( .s prints the contents of the stack.  It doesn't alter the stack.
  Very useful for debugging. Prints stack in std FORTH order, with TOS last. )

: .s		( -- )
	'<' emit depth 0 .r '>' emit
	space

	s0 @ 8 -		( sp ... )
	begin
		dup dsp@ 8 + >  ( at the top? )
	while
		dup @ .         ( print the stack element )
		space
		8-		( move down )
	repeat
	drop
	cr
;


: to immediate	( n -- )
	word		( get the name of the value )
	find		( look it up in the dictionary )
	>dfa		( get a pointer to the first cell of the data field )
	state @ if	( compiling? )
		['] lit ,		( compile lit )
		,		( compile the address of the value )
		['] ! ,		( compile ! )
	else		( immediate mode )
		!		( update it straightaway )
	then
;

( x +to val adds x to val )

: +to immediate
	word		( get the name of the value )
	find		( look it up in the dictionary )
	>dfa		( get a pointer to the first cell of the data field )
	state @ if	( compiling? )
		['] lit ,		( compile lit )
		,		( compile the address of the value )
		['] +! ,		( compile +! )
	else		( immediate mode )
		+!		( update it straightaway )
	then
;

( case...endcase is how we do switch statements in forth.  there is no generally
  agreed syntax for this, so I've gone for the syntax mandated by the ISO standard
  FORTH -- ANS-FORTH.

  some value on the stack
  case
  test1 of ... endof
  test2 of ... endof
  testn of ... endof
  ... default case
  endcase

  The case statement tests the value on the stack by comparing it for equality with
  test1, test2, ..., testn and executes the matching piece of code within of ... endof.
  If none of the test values match then the default case is executed.  Inside the ... of
  the default case, the value is still at the top of stack -- it is implicitly drop-ed
  by endcase.  When endof is executed it jumps after endcase -- ie. there is
  no "fall-through" and no need for a break statement like in C.

  The default case may be omitted.  In fact the tests may also be omitted so that you
  just have a default case, although this is probably not very useful.

  An example -- assuming that 'q', etc. are words which push the ASCII value
  of the letter on the stack:

	0 value quit
	0 value sleep
	key case
		'q' of 1 to quit endof
		's' of 1 to sleep endof
		\ default case:
		." sorry, i didn't understand key <" dup emit ." >, try again." cr
	endcase

        In some versions of FORTH, more advanced tests are supported, such as ranges, etc.
  Other versions of FORTH need you to write OTHERWISE to indicate the default case.
  As I said above, this FORTH tries to follow the ANS FORTH standard.

  The implementation of CASE...ENDCASE is somewhat non-trivial.  I'm following the
  implementations from here:
  http://www.uni-giessen.de/faq/archiv/forthfaq.case_endcase/msg00000.html

  The general plan is to compile the code as a series of IF statements:

  case				\ push 0 on the immediate-mode parameter stack
  test1 of ... endof		test1 over = if drop ... else
  test2 of ... endof		test2 over = if drop ... else
  testn of ... endof		testn over = if drop ... else
  ...  default case 		...
  endcase				drop then [then [then ...]]

  The case statement pushes 0 on the immediate-mode parameter stack, and that number
  is used to count how many then statements we need when we get to endcase so that each
  if has a matching then.  The counting is done implicitly.  If you recall from the
  implementation above of if, each if pushes a code address on the immediate-mode stack,
  and these addresses are non-zero, so by the time we get to endcase the stack contains
  some number of non-zeroes, followed by a zero.  The number of non-zeroes is how many
  times IF has been called, so how many times we need to match it with then.

  This code uses [compile] so that we compile calls to if, else, then instead of
  actually calling them while we're compiling the words below.

  As is the case with all of our control structures, they only work within word
  definitions, not in immediate mode.)

: case immediate
	0		( push 0 to mark the bottom of the stack )
;

: of immediate
	['] over ,	( compile over )
	['] = ,		( compile = )
	[compile] if	( compile if )
	['] drop ,  	( compile drop )
;

: endof immediate
	[compile] else	( endof is the same as else )
;

: endcase immediate
	['] drop ,	( compile drop )

	( keep compiling then until we get to our zero marker )
	begin
		?dup
	while
		[compile] then
	repeat
;

( cfa> is the opposite of >cfa.  It takes a codeword and tries to find the matching
  dictionary definition.  In truth, it works with any pointer into a word, not just
  the codeword pointer, and this is needed to do stack traces.

  In this FORTH this is not so easy.  In fact we have to search through the dictionary
  because we don't have a convenient back-pointer -- as is often the case in other versions
  of FORTH.  Because of this search, cfa> should not be used when performance is critical,
  so it is only used for debugging tools such as the decompiler and printing stack
  traces.

  This word returns 0 if it doesn't find a match.)

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


( These words interact with the system implementation to provide I/O facilities. Where
  possible they match the definitions on forth-standard.org )

: source-id srcid @ ;

: save-input ( -- i*k k )
  inbuf @
  >in @
  srclen @
  srcid @
  0xabacab ( magic marker on the stack )
  5
;

: restore-input ( i*k k -- )
  ( todo use abort" -- if it's possible to define abort" )
  5 <> if ." stack mismatch" -1 throw then
  0xabacab <> if ." stack mismatch" -1 throw then
  srcid !
  srclen !
  >in !
  inbuf !
;

: eof?
  >in @ srclen @ >
;

: evaluate ( i*j c-addr u -- i*k )
  >r >r
  save-input

  r> r>
  srclen !
  inbuf !
  -1 srcid !
  0 >in !

  begin
    interpret
    eof? if
      restore-input
      exit
    then
  again
;

( buffer arrays )

( Create an array of buffers. Each buffer is buf-size-bytes long
  and there are n of these buffers in the array. So this:

        16 9 []buffer data

  Creates a new buffer called "data" that contains nine 16 byte elements.
  The size of the individual elements don't have to be aligned in any way,
  so you can have 7 or 93 byte elements in your array.

  The data section of the array starts with two cells, one for n and one for the
  buffer size. This is followed by the actual elements. When executed, the resulting
  word will push the address of the first element of the buffer array onto the stack.
)

: []buffer ( el-size-bytes n <name> -- )
        create          ( el-size-bytes n )
        2dup            ( el-size-bytes n el-size-bytes n)
        ,               ( el-size-bytes n el-size-bytes )
        ,               ( n el-size-bytes )
        *               ( n-bytes )
        allot
        align
        does> ( i buffer -- addr )
        over 0< if
                ." Index is negative! " abort
        then
        2dup            ( i buffer i buffer )
        @ >= if
                ." Index > n! " abort
        then
        dup 1 cells + @ ( i buffer el-size )
        rot             ( buffer el-size i )
        * +
        2 cells +
;

( Given addr of the 1st element, return the el size of an array )

: []% ( buffer[0] -- el-size )
        1 cells - @
;

( Given addr of the 1st element, return the # elements of an array )
( Number of elements in buf array )

: []# ( buffer[0] -- len )
        2 cells - @
;

( Pull in the rest of the basic Forth boot-up code. )

boot1 evaluate
