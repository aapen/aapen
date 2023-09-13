( Some definitions to get us started. )

: star ( -- : Emit a star ) 42 emit ;
: bar ( -- : Emit a bar) star star star star cr ;
: dot ( -- : Emit a dot) star cr ;
: F ( -- : Draw an ascii art F) bar dot bar dot dot ;
: p ( n -- : Print the top of the stack followed by a newline) . cr ;

F

( Input and output base words )

: base ( n -- : Set the input and output bases.)
  dup
  forth forth.obase + !
  forth forth.ibase + !
;

: hex ( -- : Set the input and output bases to 16.)     16 base ;
: decimal ( -- : Set the input and output bases to 10.) 10 base ;

( compiling words )

: secondary! (addr -- Make the word a secondary)
  header.func + inner swap !
;

: immediate! ( f addr -- Change the immediate flag of the word at addr to f)
  header.immediate + !
;

( Debugging )

: tron  ( -- : Turn debugging on.)   1 forth forth.debug + ! ;
: troff ( -- : Turn debugging off.)  0 forth forth.debug + ! ;

( Address arithmetic )

: words ( n -- n : Number words -> number bytes ) word * ;
: aligned ( c-addr – a-addr  : Align the address.) word 1 - + word / word * ;

( Testing... )

: assert ( b desc -- if b is not true )
  "Assert: " s.
  s.
  if
    " OK"
  else
    " ** FAILED! **"
  endif
  s. cr
  clear
;

: power-of-two ( n -- n ) 
  1 swap 
  while dup 0 > 
  do
    swap 2 * 
    swap 1 -
  done
  drop
;

create by-hand (test word)
  '*push-u64 ,
  900 ,
  '*push-u64 ,
  99 ,
  '+ ,
  *stop ,
finish

'by-hand secondary!

: test-math 
  103      103  = "Equality" assert
  1 1 +      2  = "Simple addition" assert
  99 1 -    98  = "Subtraction" assert
  3 7 *     21  = "Multipication" assert
;

: test-if
  77 1    if 100 endif         100 = "If true" assert
  77 0    if 100 endif          77 = "If false" assert
  1       if 100 else 99 endif 100 = "If else true" assert
  0       if 100 else 99 endif  99 = "If else false" assert
; 

: test-loop
   0 power-of-two     1 = "While loop, zero iterations" assert
  16 power-of-two 65536 = "While loop, 16 iterations" assert
;

: test-strings
  "hello world" "hello world" s= "String comparison" assert
;

: test-create
  by-hand 999 = "Word created with create/finish" assert
;

: test-constants
  word 8 = "Word size constant" assert
;

: test-structures
  'hello header.name + @ "hello" s= "Struct offsets" assert
;

: test-all
  "Self test..." s. cr
  test-if
  test-math
  test-loop
  test-strings
  test-constants
  test-structures
  test-create
;

test-all
