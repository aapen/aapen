noecho

( save base, use decimal )
base @ decimal

peripherals 0x     b880 + constant mbox-read
mbox-read   0x       10 + constant mbox-peek
mbox-read   0x       18 + constant mbox-status
mbox-read   0x       20 + constant mbox-write

: delay ( n -- : loop n times )
  begin ?dup while 1- repeat
;

1 30 lshift constant mbox-status-empty
1 31 lshift constant mbox-status-full

: mbox-empty? mbox-status w@ mbox-status-empty and ;
: mbox-full?  mbox-status w@ mbox-status-full  and ;

: mboxflush ( -- : discard any pending messages )
  begin
    mbox-empty? not
  while
    mbox-read w@ drop
    1 delay
  repeat
;

( a -- )
: send
  begin mbox-full? while repeat         ( wait for space )
  0x f invert and                       ( clear lower 4 bits )
  8 or                                  ( assume channel 8 )
  mbox-write w!
;

( -- a )
: receive
  begin mbox-empty? while repeat        ( wait for reply )
  mbox-read w@                          ( read message )
  0x f invert and                       ( mask out channel )
;

( Temporary state )
variable message-start                  ( pointer to start of message buffer )

: values 4 * ;

( n -- a )
: msg[] values message-start @ + ;

( a w -- a' )
: w!+ over w! 4+ ;

( align addr to next 32 bit boundary )
( a -- a )
: walign 3 + 3 invert and ;

( Start a bundle of messages )
( a -- )
: draft
  dup
  message-start !
  0 w!+                                 ( reserve space for payload size )
  0 w!+                                 ( reserve space for result status )
;

( a -- )
: finish
  0 w!+                                 ( write terminator )
  0 msg[]                               ( p_cur p_start)
  -                                     ( len )
  0 msg[] w!                            ( write payload size )
;

: tags{{ scratch draft ;
: }} finish scratch send receive ;

( n a t -- a' )
: 1-1tag
  ( tag )  w!+
  1 values w!+
  1 values w!+
  swap     w!+
  walign
;

( n a t -- a' )
: 1-2tag
  ( tag )  w!+
  1 values w!+
  2 values w!+
  swap     w!+
  0        w!+
  walign
;

( n n a t -- a' )
: 2-2tag
  ( tag )  w!+
  2 values w!+
  2 values w!+
  swap     w!+
  swap     w!+
  walign
;

( n n n n a t -- a' )
: 4-4tag
  ( tag )  w!+
  4 values w!+
  4 values w!+
  swap     w!+
  swap     w!+
  swap     w!+
  swap     w!+
  walign
;

( FRAME BUFFER )

: physical-size                   rot 0x 48003 2-2tag ;
: virtual-size                    rot 0x 48004 2-2tag ;
: depth                          swap 0x 48005 1-1tag ;
: overscan                            0x 4800a 4-4tag ;
: allocate-framebuffer 16 swap 0 swap 0x 40001 2-2tag ;
: fb-pitch                     0 swap 0x 40008 1-1tag ;

( a -- a' )
: set-palette
  0x    4800b w!+
    34 values w!+                         ( 32 palette entries + offset + length )
    34 values w!+
            0 w!+                         ( offset 0 )
           32 w!+                         ( length 32 )
  0x 00000000 w!+                         ( RGB of entry 0 )
  0x 00ffffff w!+
  0x 000000ff w!+
  0x 00eeffaa w!+
  0x 00cc44cc w!+
  0x 0055cc00 w!+
  0x 00e44140 w!+
  0x 0077eeee w!+
  0x 005588dd w!+
  0x 00004466 w!+
  0x 007777ff w!+
  0x 00333333 w!+
  0x 00777777 w!+
  0x 0066ffaa w!+
  0x 00f3afaf w!+
  0x 00bbbbbb w!+                         ( RGB of entry 15 )
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+
  0x 00000000 w!+                         ( RGB of entry 31 )
  walign
;

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
    set-palette
    fb-pitch
  }}

  ( these are sensitive to the order of the tags )
  26 msg[] w@ fb !
  27 msg[] w@ fbsize !
  68 msg[] w@ fbpitch !
   6 msg[] w@ fbyres !
   5 msg[] w@ fbxres !
;

( x y -- a )
: pixel fbpitch @ * + fb @ + ;

initialize-fb drop
3    0   0 pixel c!
4 1023   0 pixel c!
5 1023 767 pixel c!
6    0 767 pixel c!

( CLOCKS )

1  constant clock-emmc
2  constant clock-uart
3  constant clock-arm
4  constant clock-core
5  constant clock-v3d
6  constant clock-h264
7  constant clock-isp
8  constant clock-sdram
9  constant clock-pixel
10 constant clock-pwm

( clock-id tag -- val )
: do-clock-query tags{{ swap 1-2tag }} 6 msg[] w@ ;
: clock-state    0x 30001 do-clock-query ;
: clock-rate     0x 30002 do-clock-query ;
: clock-rate-max 0x 30004 do-clock-query ;
: clock-rate-min 0x 30007 do-clock-query ;

echo

( restore base )
base !
