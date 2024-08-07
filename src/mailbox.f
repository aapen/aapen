noecho
base @ value mbox-old-base
decimal

peripherals 0x     b880 + constant mbox-read
mbox-read   0x       10 + constant mbox-peek
mbox-read   0x       18 + constant mbox-status
mbox-read   0x       20 + constant mbox-write

0x 40 constant cache-line

( Clean invalidate cache in a region )
( addr len -- end-addr end-len )
: dcc-reg
  begin
    dup 0>
  while
    swap dup dcc cache-line + swap cache-line -
  repeat
;

( Invalidate cache in a region )
( addr len -- end-addr end-len )
: dci-reg
  begin
    dup 0>
  while
    swap dup dci cache-line + swap cache-line -
  repeat
;

0 0x 1c -8 str-x[x#]! constant pushpsp-x0

defprim clk-freq
  CNTFRQ_EL0 0 mrs-xr w,
  pushpsp-x0          w,
;;

( get hardware timer count )
( -- n )
defprim ticks
  CNTVCT_EL0 0 mrs-xr w,
  pushpsp-x0          w,
;;

clk-freq 1000000 / constant ticks-per-micro

( spinloop until at least n micros have passed )
: delay ( n -- )
  ticks-per-micro *
  ticks +
  begin dup ticks > while repeat
  drop
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
    20 delay
  repeat
;

: stash dup >r ;
: unstash >r ;

( a -- )
: send
  begin mbox-full? while repeat ( wait for space )
  dup 0x f and
  if
    ." misaligned "
  else
    fence                       ( a         | make sure writes are complete )
    dup dup w@                  ( a a len   | get ptr and len )
    dcc-reg                     ( a a' len' | clean cache in region )
    2drop                       ( a         | )
    8 or                        ( a         | assume channel 8 )
    mbox-write w!               (           | hand off to GPU )
  then
;

( -- a )
: receive
  begin mbox-empty? while repeat (           | wait for reply )
  mbox-read w@                   ( a         | read message )
  0x f invert and                ( a         | mask out channel )
  dup dup w@                     ( a a len   | )
  dci-reg                        ( a a' len' | invalidate cache in region )
  2drop                          ( a         | )
  fence                          ( a         | make sure writes are complete )
  drop                           (           | )
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

( n n n a t -- a' )
: 3-3tag
  ( tag )  w!+
  3 values w!+
  3 values w!+
  swap     w!+
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

( CLOCKS )

1  constant clk-emmc
2  constant clk-uart
3  constant clk-arm
4  constant clk-core
5  constant clk-v3d
6  constant clk-h264
7  constant clk-isp
8  constant clk-sdram
9  constant clk-pixel
10 constant clk-pwm
11 constant clk-hevc
12 constant clk-emmc2
13 constant clk-m2mc
14 constant clk-pixel-bvb
15 constant clk-vec
16 constant clk-disp

( clock-id tag -- val )
: do-clock-query tags{{ swap 3-3tag }} 6 msg[] w@ ;
: clock-state    0 swap 0 swap 0x 30001 do-clock-query ;
: clock-rate     0 swap 0 swap 0x 30002 do-clock-query ;
: clock-rate-max 0 swap 0 swap 0x 30004 do-clock-query ;
: clock-rate-min 0 swap 0 swap 0x 30007 do-clock-query ;

: discover-clocks
  tags{{
    0x 10007         w!+                ( 'get clocks' tag )
    clk-disp 2 + 8 * w!+                ( req buf size )
    0                w!+                ( space for resp len )
    clk-disp 2 + 8 * 'A' rot            ( d: len byte addr )
    memset                              ( d: addr+len )
    walign
    scratch 0x c0 dump
  }}
  5 msg[]                               ( d: addr )
  4 msg[] w@ 0x 7fffffff and            ( d: addr bytes )
  8 /                                   ( d: addr cnt )
;

( power )

0 constant power-sdhci
1 constant power-uart0
2 constant power-uart1
3 constant power-usb-hcd
4 constant power-i2c0
5 constant power-i2c1
6 constant power-i2c2
7 constant power-spi
8 constant power-ccp2tx

: do-power-query tags{{ swap 2-2tag }} 6 msg[] w@ ;
( device-id -- power-state )
: power-state 0 swap 0x 20001 do-power-query ;
( device-id -- result )
: power-on  1 swap 0x 28001 do-power-query ;
: power-off 0 swap 0x 28001 do-power-query ;

mbox-old-base base !
echo
