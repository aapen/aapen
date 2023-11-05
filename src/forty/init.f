(Simple console control)

: cr 0x0a emit ;
: cls 0x0c emit ;

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
: draw-char (y x c -- : Draw character at position)
  fb
  [[ fb fb.vtable fb.vtable.char +]] @
  invoke-4
;

: text (y x s -- : Draw string at position)
  fb
  [[ fb fb.vtable fb.vtable.text +]] @
  invoke-4
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

(Character predicates)

8   :char-bs    let
10  :char-nl    let
13  :char-cr    let
32  :char-space let
127 :char-del   let

: char-ctrl (ch -- CNTRL-ch)
  \a -
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
  \" =
;


(String buffer)

: sb-create (pName -- : Create a new string buffer with the name)
  create
    0 ,
    16 allot
  finish
;

: sb-count (sb-addr -- n : Return the number of chars in sb)
  @
;

: sb-inc-count (sb-addr -- : Increment the sb char count.)
  dup
  @
  inc
  swap
  !
;

: sb-dec-count (sb-addr -- : Increment the sb char count.)
  dup
  @
  dup 1 >= 
  if 
    dec 
    swap
    !
  else
    2drop
  endif
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

: emit-prompt
  "forty>> " s.
;

:repl-buffer sb-create

: ignore-handler (ch --) drop ;

: insert-handler (ch --)
  dup emit 
  repl-buffer sb-append
;

: backspace-handler (ch -- : Echo the char and back up one in the buffer)
  repl-buffer sb-count 0 >
  if
    emit
    repl-buffer sb-dec-count
  else
    drop
  endif
;

: newline-handler (ch -- : Handle a newline. Echos the char, eval, reset buffer.)
  emit
  0 repl-buffer sb-append
  repl-buffer sb-string
  repl-buffer sb-clear
  eval-command
  emit-prompt
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

:handlers dtab-create

'backspace-handler handlers char-bs  dtab-set
'backspace-handler handlers char-del dtab-set
'newline-handler   handlers char-nl  dtab-set
'newline-handler   handlers char-cr  dtab-set

'insert-handler    handlers char-space \~ dtab-set-range

'line-demo-handler handlers \^ dtab-set

: handle-one (ch -- : Handle a single character)
  handlers key dtab-trigger
;


: repl-loop (-- : Prompt for and execute words, does not return)
  emit-prompt
  while
    1
  do
    handle-one
  done
;

(Repl)

: read-ch ( -- ch : read with echo)
  key
  dup emit
;

: read-command (sb-addr --)
  dup sb-clear
  emit-prompt
  read-ch
  while
    dup newline? not
  do
    dup backspace?
    if
      drop
      dup sb-dec-count
    else
      over sb-append
    endif
    read-ch
  done
  drop
  dup 0 swap sb-append
  drop
;


: repl (--)
  "REPL in forth, type 'quit' to exit" s. cr cr
  repl-buffer read-command
  repl-buffer sb-string
  while
    dup "quit" s= not
  do
    eval-command
    repl-buffer read-command
    repl-buffer sb-string
  done
  "Exit REPL!" s. cr
;

:input-buffer sb-create

: handle (--)
  "yes>> " s.
  read-ch
  while
    dup 17 = not
  do
    input-buffer
    handlers 
    rot
    ?stack
    dtab-trigger
    read-ch
  done
  drop
  dup 0 swap sb-append
  drop
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

(Screen editing)

fbcons fbcons.width  + @     :scr-width  let
fbcons fbcons.height + @     :scr-height let
scr-width scr-height * :scr-length let

: scr-create (name -- pscreen : Create a screen buffer)
  create
    scr-length ballot
  finish
;

:screen scr-create

: scr-fill (ch screenp --)
  scr-length set-mem
;

: scr-clear
  char-space swap scr-length set-mem
;

: scr-y (screen n-byte -- i-line)
  scr-width /
;

: scr-x (screen n-byte -- i-row)
  scr-width %
;

: scr-offset (x y -- mem-offset)
  scr-width * +
;

: scr-set (screenp x y ch -- : set the char at x y in screen)
  rot rot            (stack: screenp ch x y)
  scr-offset         (stack: screenp ch offset)
  rot                (stack: ch offset screenp)
  +                  (stack: ch p)
  !b
;
  

: scr-sync (screenp -- )
  scr-length times
    dup ->stack + @b
    ->stack scr-x
    ->stack scr-y
    rot
    draw-char
  repeat
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

cr cr cr
"************* Nygard/Olsen Forth V40 **************" s. cr
mem-total 1024 / . "K RAM SYSTEM " s. mem-available . " FORTH BYTES FREE" s. cr
"READY" s. cr
cr cr

"Forty REPL" s. cr cr
repl-loop
