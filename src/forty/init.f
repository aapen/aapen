(Simple console control)

: cr 0x0a emit ;
: cls 0x0c emit ;
: p ( n -- : Print the top of the stack followed by a newline) . cr ;

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

: assert-verbose ( b desc -- if b is not true )
  "Assert: " s.
  s.
  if
    " OK"
  else
    " ** FAILED! **"
  endif
  s. cr
;

: assert ( b desc -- if b is not true )
  swap
  if
    drop
  else
    s. " **Assertion FAILED! **" s. cr
  endif
;

: assert-in-word (addr wordp desc -- :Assert that the given addr is part of the word defintion)
  rot rot
  3dup
  >= swap assert
  dup header.len + @ +
  <= swap assert
;

( Address arithmetic )

: words ( n -- n : Number words -> number bytes ) word * ;
: aligned ( c-addr – a-addr  : Align the address.) word 1 - + word / word * ;

:[[ create
finish

: +]] 0 while swap dup [[ = not do + done drop ;

(Drawing)
: draw-char (bg fg y x c -- : Draw character at position)
  fb
  [[ fb fb.vtable fb.vtable.char +]] @
  invoke-6
;

: text (bg fg y x s -- : Draw string at position)
  fb
  [[ fb fb.vtable fb.vtable.text +]] @
  invoke-6
;

: line  (color y2 x2 y1 x1 -- : Draw a colored line)
  fb
  [[ fb fb.vtable fb.vtable.line +]] @
  invoke-6
;

: fill  (color bottom right top left -- : Fill a rectangle with color)
  fb
  [[ fb fb.vtable fb.vtable.fill +]] @
  invoke-6
;

: blit  (dst-y dst-x src-h src-w src-y src-x -- : Copy a rectangle)
  fb
  [[ fb fb.vtable fb.vtable.blit +]] @
  invoke-7
;


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

: data-address (p-word -- p-data : Given a word ptr, return the word data ptr)
  header.*len +
;

(Character)

8   :char-bs    let
10  :char-nl    let
13  :char-cr    let
27  :char-esc   let
32  :char-space let
127 :char-del   let

: char-ctrl (ch -- CNTRL-ch)
  \a - inc
;

: backspace?
  dup
  char-bs   = swap
  char-del  =
  or
;

: newline? char-nl = ;

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
  0x22 =
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

: set-bg (fg bg -- : Set the text bg color)
  [[ fbcons fbcons.display display.current_bg +]] !b
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

: set-text-fg (color-n --)
  0x90 + emit
;

: set-text-bg (color-n -- cntr-char-set color)
  0xa0 + emit
;

: set-colors (fg bg -- : Set the text colors)
  set-text-bg
  set-text-fg
;

: c64-colors
  light-blue blue set-colors
;

: default-colors
  white black set-colors
;


(Screen dimensions)

[[ fbcons fbcons.display display.num_cols  +]] @  :scr-cols let
[[ fbcons fbcons.display display.num_rows  +]] @  :scr-rows let

[[ fb fb.xres +]] @w :scr-xres let
[[ fb fb.yres +]] @w :scr-yres let

(Key Dispatch Table: dtab)

: dtab-set (word-address dtab key -- : Set handler for key to word-adress)
  word * + (word-address dtab-entry-addr)
  !
;

: dtab-set-range (word-address dtab key1 key2--)
  for-range
    2dup
    ->stack
    dtab-set
  repeat
  2drop
;

: dtab-create (dt-name -- dtab: Create a 128 entry key dispatch table)
  dup
  create
    128 allot
  finish
  lookup data-address 0x0000 swap 0 128 dtab-set-range
;

: dtab-lookup (dtab ch -- handler-word: Lookup the handler for the ch)
  word * +
  @
;

: dtab-trigger (dtab ch -- : Trigger the word associated with ch)
  dup rot swap
  dtab-lookup
  dup if
    exec
  else
    drop
  endif
;

:repl-buffer create
  scr-cols inc ballot
finish

:repl-insert create
  1 ,
finish

: repl-insert? ( -- insert-flag) repl-insert @ ;

: repl-insert-toggle (--)
  repl-insert @ not repl-insert !
;

: emit-prompt
  0x8a emit "forty>> " s. 0x8b emit
;

: emit-prompt
  "OK" s. cr
;

: ignore-handler (ch --) drop ;

: insert-handler (ch --)
  repl-insert? if
    0xb0 emit
  endif
  emit
;

: insert-handler (ch --) emit ;

: echo-handler (ch -- ) emit ;

: newline-handler (ch -- : Handle a newline. Echos the char, eval, reset buffer.)
  drop
  repl-buffer -1 get-scr-text
  dup s~
  cr
  eval-command
  emit-prompt
  (char-nl emit eval-command emit-prompt)
;

: redisplay-handler
  0xff emit
;

: toggle-insert-handler
  drop
  repl-insert-toggle
;

: previous-handler drop 0x80 emit ;
: next-handler     drop 0x81 emit ;
: back-handler     drop 0x82 emit ;
: forward-handler  drop 0x83 emit ;
: bol-handler      drop 0x84 emit ;
: eol-handler      drop 0x85 emit ;
: redraw-handler   "redraw! " s~ drop 0xff emit ;

: escape-handler
  drop       (Discard the escape)
  key drop   (Discard [)
  key
  dup 65 = if
    previous-handler
    return
  endif
  dup 66 = if
    next-handler
    return
  endif
  dup 67 = if
    forward-handler
    return
  endif
  dup 68 = if
    back-handler
    return
  endif
  dup 70 = if
    eol-handler
    return
  endif
  dup 72 = if
    bol-handler
    return
  else
    "??? esc [ " s~ ~
  endif
;

: line-demo-handler (ch -- : Draw some pretty lines)
  drop
  0 250 for-range
    20 300              (x1 y1)
    1000 ->stack 3 *    (x2 y2)
    ->stack 16 %        (c)
    line
  repeat
;

: ex-handler
  0xb0 emit
  (\Q emit)
;

: dump-text-handler
  0xf0 emit
;

:handlers dtab-create

'echo-handler      handlers char-bs  dtab-set
'echo-handler      handlers char-del dtab-set
'newline-handler   handlers char-nl  dtab-set
'newline-handler   handlers char-cr  dtab-set
'escape-handler    handlers char-esc dtab-set

'bol-handler           handlers \a char-ctrl dtab-set
'back-handler          handlers \b char-ctrl dtab-set
'dump-text-handler     handlers \d char-ctrl dtab-set
'eol-handler           handlers \e char-ctrl dtab-set
'forward-handler       handlers \f char-ctrl dtab-set
'toggle-insert-handler handlers \i char-ctrl dtab-set
'next-handler          handlers \n char-ctrl dtab-set
'previous-handler      handlers \p char-ctrl dtab-set
'redraw-handler        handlers \r char-ctrl dtab-set
'ex-handler            handlers \x char-ctrl dtab-set

'insert-handler    handlers char-space \~ dtab-set-range

'line-demo-handler handlers \^ dtab-set

: handle-one (ch -- : Handle a single character)
  handlers key dtab-trigger
;

: repl (-- : Prompt for and execute words, does not return)
  emit-prompt
  while
    1
  do
    handle-one
  done
;

( Testing... )

: power-of-two ( n -- n )
  1 swap
  while dup 0 >
  do
    swap 2 *
    swap 1 -
  done
  drop
;

: sum-ints ( n -- sum : add up all the numbers from 1 to n)
  0 swap
  times
    ->stack 1 + +
  repeat
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
  "." s.
  103      103  = "Equality" assert clear
  1 1 +      2  = "Simple addition" assert clear
  99 1 -    98  = "Subtraction" assert clear
  3 7 *     21  = "Multipication" assert clear
  0 100 - -100  = "Negative numbers" assert clear
  11 5 %     1  = "Modulo" assert clear
;

: test-if
  "." s.
  77 1    if 100 endif         100 = "If true" assert clear
  77 0    if 100 endif          77 = "If false" assert clear
  1       if 100 else 99 endif 100 = "If else true" assert clear
  0       if 100 else 99 endif  99 = "If else false" assert clear
;

: test-loop
  "." s.
   0 power-of-two     1 = "While loop, zero iterations" assert clear
  16 power-of-two 65536 = "While loop, 16 iterations" assert clear
  0  sum-ints         0 = "Repeat loop, 0 iterations" assert clear
  3  sum-ints         6 = "Repeat loop, 3 iterations" assert clear
  10 sum-ints        55 = "Repeat loop, 10 iterations" assert clear
;

: test-strings
  "." s.
  "hello world" "hello world" s= "String comparison" assert clear
;

: test-create
  "." s.
  by-hand 999 = "Word created with create/finish" assert clear
;

: test-constants
  "." s.
  word 8 = "Word size constant" assert clear
;

: test-structures
  "." s.
  'hello header.name + @ "hello" s= "Struct offsets" assert clear
;

(Retro startup!)

hello
hello
hello
0xf0 emit
c64-colors
cls

: test-all
  "Self test..." s.
  test-if
  test-math
  test-loop
  test-strings
  test-constants
  test-structures
  test-create
  "Done" s. cr
;

test-all

(Temporary words for debugging)
: dump-usb  ( -- : Dump USB registers )
  [[ hal hal.usb +]]
  [[ hal hal.usb usb.vtable usb.vtable.dumpStatus +]] @
  invoke-1
;


: aapen-logo
  yellow set-text-fg
  "                 AAA                              AAA                                                                        " s. cr
  "                A:::A                            A:::A                                                                       " s. cr
  "               A:::::A                          A:::::A                                                                      " s. cr
  green set-text-fg
  "              A:::::::A                        A:::::::A                                                                     " s. cr
  "             A:::::::::A                      A:::::::::A          AAAAA   AAAAAAAAA       AAAAAAAAAAAA    AAAA  AAAAAAAA    " s. cr
  "            A:::::A:::::A                    A:::::A:::::A         A::::AAA:::::::::A    AA::::::::::::AA  A:::AA::::::::AA  " s. cr
  red set-text-fg
  "           A:::::A A:::::A                  A:::::A A:::::A        A:::::::::::::::::A  A::::::AAAAA:::::AAA::::::::::::::AA " s. cr
  "          A:::::A   A:::::A                A:::::A   A:::::A       AA::::::AAAAA::::::AA::::::A     A:::::AAA:::::::::::::::A" s. cr
  yellow set-text-fg
  "         A:::::A     A:::::A              A:::::A     A:::::A       A:::::A     A:::::AA:::::::AAAAA::::::A  A:::::AAAA:::::A" s. cr
  "        A:::::AAAAAAAAA:::::A            A:::::AAAAAAAAA:::::A      A:::::A     A:::::AA:::::::::::::::::A   A::::A    A::::A" s. cr
  "       A:::::::::::::::::::::A          A:::::::::::::::::::::A     A:::::A     A:::::AA::::::AAAAAAAAAAA    A::::A    A::::A" s. cr
  green set-text-fg
  "      A:::::AAAAAAAAAAAAA:::::A        A:::::AAAAAAAAAAAAA:::::A    A:::::A    A::::::AA:::::::A             A::::A    A::::A" s. cr
  "     A:::::A             A:::::A      A:::::A             A:::::A   A:::::AAAAA:::::::AA::::::::A            A::::A    A::::A" s. cr
  red set-text-fg
  "    A:::::A               A:::::A    A:::::A               A:::::A  A::::::::::::::::A  A::::::::AAAAAAAA    A::::A    A::::A" s. cr
  "   A:::::A                 A:::::A  A:::::A                 A:::::A A::::::::::::::AA    AA:::::::::::::A    A::::A    A::::A" s. cr
  "  AAAAAAA                   AAAAAAAAAAAAAA                   AAAAAAAA::::::AAAAAAAA        AAAAAAAAAAAAAA    AAAAAA    AAAAAA" s. cr
  "                                                                  A:::::A                                                  " s. cr
  yellow set-text-fg
  "                                                                  A:::::A                                                  " s. cr
  "                                                                 A:::::::A                                                 " s. cr
  "                                                                 A:::::::A                                                 " s. cr
  green set-text-fg
  "                                                                 A:::::::A                                                 " s. cr
  "                                                                 AAAAAAAAA                                                 " s. cr
  light-blue set-text-fg
;

cr cr
aapen-logo
cr
"V 0.01" s. cr
mem-total 1024 / . "K RAM SYSTEM " s. mem-available . " FORTH BYTES FREE" s. cr
"READY" s. cr
cr cr

"Forty REPL" s. cr cr
(repl)
