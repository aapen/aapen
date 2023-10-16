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

:[[ create 
finish

: +]] 0 while swap dup [[ = not do + done drop ;

(Utilities)

: inc 1 + ;
: dec 1 - ;

: inc! dup @ inc swap ! ;
: dec! dup @ dec swap ! ;

: word-len (word-addr -- len)
  header.len + @
;

: word-data-len (pWord - n : Return the number of data bytes associated with word)
  word-len
  header.*len -
;

: word-address (p-data -- p-word : Given a word data ptr, return word ptr)
  header.*len - 
;

(String buffer)

: sb-create (pName -- : Create a new string buffer with the name)
  create
    0 ,
    16 allot
  finish
;

: sb-inc-count (sb-addr -- : Increment the sb char count.)
  dup
  @
  inc
  swap
  !
;

: sb-poke-char (ch sb-addr -- : Add a character at the current position.)
  dup
  @  word + +
  !b
;
  
: sb-append (ch sb-addr --  : Append a new char onto the buffer.)
  dup rot swap
  sb-poke-char
  sb-inc-count
;

: sb-string (sb-addr -- str : Push the address of the string in the sb)
  word +
;

: sb-clear (sb-word --  : Clear this buffer)
  0 swap !
;

(Character predicates)


( Testing... )

32 :char-space let
13 :char-cr    let
10 :char-nl    let

: whitespace? (ch -- b)
  dup dup
  char-space = rot
  char-cr    = rot
  char-nl    = rot
  or or
;

: digit? (ch -- b)
  dup
  \0 >=
  swap
  \9 <=
  and
;

: dquote? (ch -- b)
  \" =
;

(Repl)

: read-ch ( -- ch : read with echo)
  key
  dup emit
;


: read-token (sb-addr --)
  dup sb-clear
  read-ch
  while
    dup whitespace? not
  do
    over sb-append
    read-ch
  done
  drop
  dup 0 swap sb-append
;

:input-buffer sb-create

: read-eval ( -- <results> : read one word, evaluate it)
  input-buffer read-token 
  sb-string eval
;


(System status)


: mem-manager (-- addr : Push the address of the memory struct)
  forth forth.memory + 
;

: mem-total ( -- n : Push total number of bytes avail.)
  mem-manager memory.length + @w
;

: mem-used ( -- n : Push number of bytes of memory currently used)
  mem-manager memory.current + @
  mem-manager memory.p + @
  -
;

: mem-available ( -- n : Push number bytes of memory currently available)
  mem-total mem-used -
;

(Colors)

: set-fg (fg bg -- : Set the text bg color)
  fb fb.fg + !b
;

: set-bg (fg bg -- : Set the text fg color)
  fb fb.bg + !b
;

: set-colors (fg bg -- : Set the text colors)
  set-bg
  set-fg
;

 0 :black       let
 1 :white       let
 2 :red         let
 3 :cyan        let
 4 :violet      let
 5 :green       let
 6 :blue        let
 7 :yellow      let
 8 :orange      let
 9 :brown       let
10 :light-red   let
11 :dark-grey   let
12 :grey        let
13 :light-green let
14 :light-blue  let
15 :light-grey  let

: c64-colors 
  light-blue blue set-colors 
;

: default-colors 
  white black set-colors 
;

(Assertions)

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

:by-hand create
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
  0 100 - -100  = "Negative numbers" assert
  11 5 %     1  = "Modulo" assert
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

(Retro startup!)

c64-colors cls

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

cr cr cr
"************* Nygard/Olsen Forth V40 **************" s. cr
mem-total 1000 / . "K RAM SYSTEM " s. 
mem-available . " FORTH BYTES FREE" s. cr
"READY" s. cr
cr cr

default-colors
