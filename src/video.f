base @ decimal

( FRAME BUFFER )

: physical-size                   rot 0x48003 2-2tag ;
: virtual-size                    rot 0x48004 2-2tag ;
: depth                          swap 0x48005 1-1tag ;
: overscan                            0x4800a 4-4tag ;
: allocate-framebuffer 16 swap 0 swap 0x40001 2-2tag ;
: fb-pitch                     0 swap 0x40008 1-1tag ;

( a -- a' )
: set-palette
     0x4800b w!+
   34 values w!+                         ( 32 palette entries + offset + length )
   34 values w!+
           0 w!+                         ( offset 0 )
          32 w!+                         ( length 32 )
  0x00000000 w!+                         ( RGB of entry 0 )
  0x00ffffff w!+
  0x000000ff w!+
  0x00eeffaa w!+
  0x00cc44cc w!+
  0x0055cc00 w!+
  0x00e44140 w!+
  0x0077eeee w!+
  0x005588dd w!+
  0x00004466 w!+
  0x007777ff w!+
  0x00333333 w!+
  0x00777777 w!+
  0x0066ffaa w!+
  0x00f3afaf w!+
  0x00bbbbbb w!+                         ( RGB of entry 15 )
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+
  0x00ffffff w!+                         ( RGB of entry 31 )
  walign
;

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

light-blue value fg
blue       value bg

variable fb
variable fbsize
variable fbpitch
variable fbxres
variable fbyres

: initialize-fb
  tags{{
    768 1024 physical-size
    768 1024 virtual-size
    8 depth
    0 swap 0 swap 0 swap 0 swap overscan
    allocate-framebuffer
    fb-pitch
    set-palette
  }}

  ( these are sensitive to the order of the tags )
  26 msg[] w@ 0x3fffffff and fb !
  27 msg[] w@ fbsize !
  31 msg[] w@ fbpitch !
   6 msg[] w@ fbyres !
   5 msg[] w@ fbxres !
;

( x y -- a )
: pixel fbpitch @ * + fb @ + ;

initialize-fb

( cx cy -- a )
: char-pixel
  16 * swap 8 * swap pixel
;

1024 8 / constant screen-cols
768 16 / constant screen-rows

0 value cursorx
0 value cursory

: next-line
  0 to cursorx
  cursory 1+
  dup screen-rows >= if
    drop
    0 to cursory
  else
    to cursory
  then
;

: next-char
  cursorx 1+
  dup screen-cols >= if
    drop next-line
  else
    to cursorx
  then
;

( ch -- )
: emit bg fg fbpitch @ cursorx cursory char-pixel drawchar next-char ;
: cr 0 to cursorx next-line ;
: home 0 to cursorx 0 to cursory ;

( addr len -- )
: tell
  begin
    dup 0>
  while
    swap dup c@ emit 1+ swap 1-
  repeat
  2drop
;

: aapen-logo
  home cr cr
  yellow to fg
  s"                 AAA                              AAA                                                                        " tell cr
  s"                A:::A                            A:::A                                                                       " tell cr
  s"               A:::::A                          A:::::A                                                                      " tell cr
  green to fg
  s"              A:::::::A                        A:::::::A                                                                     " tell cr
  s"             A:::::::::A                      A:::::::::A          AAAAA   AAAAAAAAA       AAAAAAAAAAAA    AAAA  AAAAAAAA    " tell cr
  s"            A:::::A:::::A                    A:::::A:::::A         A::::AAA:::::::::A    AA::::::::::::AA  A:::AA::::::::AA  " tell cr
  red to fg
  s"           A:::::A A:::::A                  A:::::A A:::::A        A:::::::::::::::::A  A::::::AAAAA:::::AAA::::::::::::::AA " tell cr
  s"          A:::::A   A:::::A                A:::::A   A:::::A       AA::::::AAAAA::::::AA::::::A     A:::::AAA:::::::::::::::A" tell cr
  yellow to fg
  s"         A:::::A     A:::::A              A:::::A     A:::::A       A:::::A     A:::::AA:::::::AAAAA::::::A  A:::::AAAA:::::A" tell cr
  s"        A:::::AAAAAAAAA:::::A            A:::::AAAAAAAAA:::::A      A:::::A     A:::::AA:::::::::::::::::A   A::::A    A::::A" tell cr
  s"       A:::::::::::::::::::::A          A:::::::::::::::::::::A     A:::::A     A:::::AA::::::AAAAAAAAAAA    A::::A    A::::A" tell cr
  green to fg
  s"      A:::::AAAAAAAAAAAAA:::::A        A:::::AAAAAAAAAAAAA:::::A    A:::::A    A::::::AA:::::::A             A::::A    A::::A" tell cr
  s"     A:::::A             A:::::A      A:::::A             A:::::A   A:::::AAAAA:::::::AA::::::::A            A::::A    A::::A" tell cr
  red to fg
  s"    A:::::A               A:::::A    A:::::A               A:::::A  A::::::::::::::::A  A::::::::AAAAAAAA    A::::A    A::::A" tell cr
  s"   A:::::A                 A:::::A  A:::::A                 A:::::A A::::::::::::::AA    AA:::::::::::::A    A::::A    A::::A" tell cr
  s"  AAAAAAA                   AAAAAAAAAAAAAA                   AAAAAAAA::::::AAAAAAAA        AAAAAAAAAAAAAA    AAAAAA    AAAAAA" tell cr
  s"                                                                  A:::::A                                                    " tell cr
  yellow to fg
  s"                                                                  A:::::A                                                    " tell cr
  s"                                                                 A:::::::A                                                   " tell cr
  s"                                                                 A:::::::A                                                   " tell cr
  green to fg
  s"                                                                 A:::::::A                                                   " tell cr
  s"                                                                 AAAAAAAAA                                                   " tell cr
  light-blue to fg
;

: cls
  home
  screen-rows screen-cols *
  begin dup 0> while 32 emit 1- repeat drop
  home
;

cls
aapen-logo
cr
s" V 0.01" tell cr
s" READY" tell cr

base !
