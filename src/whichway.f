: 'i' [ char i ] literal ;
: 'j' [ char j ] literal ;
: 'k' [ char k ] literal ;
: 'l' [ char l ] literal ;
: 'm' [ char m ] literal ;

: up    ( n -- ) get-xy 1- at-xy ;
: down  ( n -- ) get-xy 1+ at-xy ;
: left  ( n -- ) get-xy swap 1- swap at-xy ;
: right ( n -- ) get-xy swap 1+ swap at-xy ;
: way.home ( n -- ) drop home ;

: min ( n1 n2 -- n ) 2dup < if drop else nip then ;
: max ( n1 n2 -- n ) 2dup > if drop else nip then ;
: clamp ( u lb ub -- u ) rot min max ;

: in-bounds
  get-xy
  0 screen-rows 1- clamp
  swap
  0 screen-cols 1- clamp
  swap
  at-xy
;

1 cells 256 []buffer keymap

' emit     0 keymap !
0 keymap dup cell+ 255 cells cmove \ copy emit's xt into all cells of the keymap
' quit     'esc' keymap !
' up       'i' keymap !
' left     'j' keymap !
' way.home 'k' keymap !
' right    'l' keymap !
' down     'm' keymap !

: ?way
  begin key dup keymap @execute in-bounds again
;

0 constant english
1 constant french
2 constant german
3 constant aussie

: english-greet ." Hello, chap " ;
: french-greet  ." Bonjour! " ;
: german-greet  ." Achtung schweinhund! " ;
: aussie-greet  ." G'day mate " ;

create greetings
' english-greet ,
' french-greet ,
' german-greet ,
' aussie-greet ,

\ 1 cells 4 []buffer greetings

\ : init-greetings
\   ['] english-greet english greetings !
\   ['] french-greet  french greetings !
\   ['] german-greet  german greetings !
\   ['] aussie-greet  aussie greetings !
\ ;

\ init-greetings

: greeting ( n -- ) cells greetings + @execute ;
