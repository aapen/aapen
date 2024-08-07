( noecho )
base @ value sd-old-base
decimal

peripherals 0x   200000 + constant gpio-base
gpio-base   0x        0 + constant gpio-fsel0
gpio-base   0x        4 + constant gpio-fsel1
gpio-base   0x        8 + constant gpio-fsel2
gpio-base   0x        c + constant gpio-fsel3
gpio-base   0x       10 + constant gpio-fsel4
gpio-base   0x       14 + constant gpio-fsel5
gpio-base   0x       1c + constant gpio-set0
gpio-base   0x       20 + constant gpio-set1
gpio-base   0x       28 + constant gpio-clr0
gpio-base   0x       2c + constant gpio-clr1
gpio-base   0x       34 + constant gpio-lev0
gpio-base   0x       38 + constant gpio-lev1
gpio-base   0x       40 + constant gpio-eds0
gpio-base   0x       44 + constant gpio-eds1
gpio-base   0x       4c + constant gpio-ren0
gpio-base   0x       50 + constant gpio-ren1
gpio-base   0x       58 + constant gpio-fen0
gpio-base   0x       5c + constant gpio-fen1
gpio-base   0x       64 + constant gpio-hen0
gpio-base   0x       68 + constant gpio-hen1
gpio-base   0x       70 + constant gpio-len0
gpio-base   0x       74 + constant gpio-len1
gpio-base   0x       7c + constant gpio-paren0
gpio-base   0x       80 + constant gpio-paren1
gpio-base   0x       88 + constant gpio-afen0
gpio-base   0x       8c + constant gpio-afen1
gpio-base   0x       94 + constant gpio-pud
gpio-base   0x       98 + constant gpio-pudclk0
gpio-base   0x       9c + constant gpio-pudclk1

peripherals 0x   300000 + constant emmc-base
emmc-base   0x        0 + constant emmc-arg2
emmc-base   0x        4 + constant emmc-blksizecnt
emmc-base   0x        8 + constant emmc-arg1
emmc-base   0x        c + constant emmc-cmdtm
emmc-base   0x       10 + constant emmc-resp0
emmc-base   0x       14 + constant emmc-resp1
emmc-base   0x       18 + constant emmc-resp2
emmc-base   0x       1c + constant emmc-resp3
emmc-base   0x       20 + constant emmc-data
emmc-base   0x       24 + constant emmc-status
emmc-base   0x       28 + constant emmc-control0
emmc-base   0x       2c + constant emmc-control1
emmc-base   0x       30 + constant emmc-irpt
emmc-base   0x       34 + constant emmc-irpt-mask
emmc-base   0x       38 + constant emmc-irpt-en
emmc-base   0x       3c + constant emmc-control2
emmc-base   0x       88 + constant emmc-tune-step
emmc-base   0x       fc + constant emmc-slotisr-ver

1 32 lshift 1- constant ~0

: clear-all! 0 swap w! ;
: set-all!  ~0 swap w! ;

( nbits shift v -- (v>>shift)&((1<<bits+1)-1) )
: bits> swap rshift 1 rot lshift 1- and ;

( v f shift -- v|f<<shift )
: >bits lshift or ;

( nbits shift v -- v & ~(1<<nbits)-1 )
: 0bits
  swap rot 1 swap lshift 1-
  swap lshift invert and
;

( nbits shift a -- )
: clear-bits! dup -rot w@ 0bits swap w! ;

: cmd          24 lshift ;
: is-data     1 21 >bits ;
: multiblock  1  5 >bits ;
: rbits-48   2 16 >bits ;
: rbits-136  1 16 >bits ;
: rbits-48b  3 16 >bits ;
: from-card   1  4 >bits ;
: counted     1  1 >bits ;
: use-rca     1 32 >bits ;
: delay-100   1 33 >bits ;
: delay-1000  2 33 >bits ;
: is-app      1 35 >bits ;
: rtype-1     1 36 >bits ;
: rtype-1b    2 36 >bits ;
: rtype-2i    3 36 >bits ;
: rtype-2s    4 36 >bits ;
: rtype-3     5 36 >bits ;
: rtype-6     6 36 >bits ;
: rtype-7     7 36 >bits ;

: cmd.is-app?  0x 800000000 and 0<> ;
: cmd.is-rca?  0x 100000000 and 0<> ;
: cmd.is-data? 0x    200000 and 0<> ;
: cmd.code     0x  ffffffff and ;
: cmd.index    24 rshift 0x 3f and ;
: cmd.delay    33 rshift 0x 3 and ;
: cmd.rbits    16 rshift 0x 3 and ;
: cmd.rtype    36 rshift 0x 7 and ;

 0 cmd                                                         constant cmd-go-idle
 2 cmd rbits-136 rtype-2i                                      constant cmd-all-send-cid
 3 cmd rbits-48  rtype-6                                       constant cmd-send-rel-addr
 4 cmd                                                         constant cmd-set-dsr
 6 cmd rbits-48  rtype-1                                       constant cmd-switch-func
 6 cmd rbits-48  rtype-1  is-app                               constant cmd-set-bus-width
 7 cmd rbits-48b rtype-1b use-rca                              constant cmd-card-select
 8 cmd rbits-48  rtype-7  delay-100                            constant cmd-send-if-cond
 9 cmd rbits-136 rtype-2s use-rca                              constant cmd-send-csd
10 cmd rbits-136 rtype-2s use-rca                              constant cmd-send-cid
11 cmd rbits-48  rtype-1                                       constant cmd-volt-switch
12 cmd rbits-48b rtype-1b                                      constant cmd-stop-xfer
13 cmd rbits-48  rtype-1  use-rca                              constant cmd-send-status
13 cmd rbits-48  rtype-1  use-rca is-app                       constant cmd-sd-status
15 cmd                    use-rca                              constant cmd-go-inactive
16 cmd rbits-48b rtype-1                                       constant cmd-set-blocklen
17 cmd rbits-48  rtype-1  is-data from-card                    constant cmd-read-single
18 cmd rbits-48  rtype-1  is-data from-card multiblock counted constant cmd-read-multi
19 cmd rbits-48  rtype-1                                       constant cmd-send-tuning
20 cmd rbits-48b rtype-1b                                      constant cmd-speed-class
22 cmd rbits-48  rtype-1  is-app                               constant cmd-send-num-wrbl
23 cmd rbits-48  rtype-1                                       constant cmd-set-blockcnt
23 cmd rbits-48  rtype-1  is-app                               constant cmd-send-num-ers
24 cmd rbits-48  rtype-1  is-data                              constant cmd-write-single
25 cmd rbits-48  rtype-1  is-data multiblock counted           constant cmd-write-multi
27 cmd rbits-48  rtype-1                                       constant cmd-program-csd
28 cmd rbits-48b rtype-1b                                      constant cmd-set-write-pr
29 cmd rbits-48b rtype-1b                                      constant cmd-clr-write-pr
30 cmd rbits-48  rtype-1                                       constant cmd-snd-write-pr
32 cmd rbits-48  rtype-1                                       constant cmd-erase-wr-st
33 cmd rbits-48  rtype-1                                       constant cmd-erase-wr-end
38 cmd rbits-48b rtype-1b                                      constant cmd-erase
41 cmd rbits-48  rtype-3  delay-1000 is-app                    constant cmd-send-op-cond
42 cmd rbits-48  rtype-1                                       constant cmd-lock-unlock
42 cmd rbits-48  rtype-1  is-app                               constant cmd-set-clr-det
51 cmd rbits-48  rtype-1  is-data from-card is-app             constant cmd-send-scr
55 cmd                                                         constant cmd-app
55 cmd rbits-48  rtype-1  use-rca                              constant cmd-app-rca
56 cmd rbits-48  rtype-1                                       constant cmd-gen-cmd

0x ff9c004 constant r1-errors-mask

1 constant etout ( timeout )
2 constant eirpt ( interrupt mismatch )
3 constant efail ( cmd failed )
4 constant erbad ( response indicates error )

( n -- n|throws )
: tout? dup ticks < if ." throwing etout" cr etout throw then ;

( micros mask addr -- )
: await-clear
  ." await clear"
  rot ticks + -rot
  begin
    dup w@ 2 pick               ( end-ticks mask addr val mask )
    and 0<>                     ( end-ticks mask addr notclear )
  while                         ( end-ticks mask addr )
    rot tout? -rot
  repeat
  drop drop drop
;

( todo: duplication between await-clear and await-set )
( micros mask addr -- )
: await-set
  ." await set"
  rot ticks + -rot
  begin
    dup w@ 2 pick
    and 0=
  while
    rot tout? -rot
  repeat
  drop drop drop
;

( todo: there has to be a better way to make an array variable )
2 cells allot constant sdcard.csd
2 cells allot constant sdcard.cid
variable sdcard.status
variable sdcard.card-state
variable sdcard.rca
variable sdcard.ocr
variable sdcard.scr
variable sdcard.block-size
variable sdcard.card-type
variable sdcard.capacity

( fn pin -- )
: gpio-fsel
  10 /mod                       ( fn inreg reg# -- )
  4 * gpio-fsel0 +              ( fn inreg regaddr )
  -rot                          ( reg fn inreg )
  3 * lshift                    ( reg fn mask )
  swap w!
;

( pin -- )
: gpio-pull-up
  0 gpio-pud w!
  150 delay
  dup 1 swap lshift gpio-pud w!
  150 delay
  32 /mod
  4 * gpio-pudclk0 +
  1 rot lshift swap tuck w!
  150 delay
  0 swap w!
;

: card-state-name
  case
    0 of s" idle" endof
    1 of s" ready" endof
    2 of s" identify" endof
    3 of s" standby" endof
    4 of s" transmit" endof
    5 of s" data" endof
    6 of s" receive" endof
    7 of s" prog" endof
    8 of s" disable" endof
  endcase
;

: matches ( n1 n2 -- n1 b ) over and 0<> ;

( irpt -- )
: await-interrupt
  ." await-interrupt: " .s
  >r ( p: 0, r: 1 )
  1000000 ticks +               ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  begin
    emmc-irpt w@ rsp@ @ and 0=  ( end-ticks b ) ( p: 0 end-ticks match?, r: 1 )
  while                         ( end-ticks ) ( p: 0 end-ticks, r: 1 )
    tout?                       ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  repeat
  drop

  ." irpt observed: " .s

  r> emmc-irpt w!               ( clear the interrupt we were waiting for )
  emmc-irpt w@

  ." irpt observed (cleared): " .s

  0x   10000 matches if etout throw then
  0x  100000 matches if etout throw then
  0x 17f8000 matches if eirpt throw then
  drop

  ." after irpt: " .s
;

( inhibit -- )
: not-busy?
  ." not-busy? " dup .x cr
  >r
  1000000 ticks +
  begin
    emmc-status w@ 0x rsp@ @ and      ( indicated inhibit bit )
    emmc-irpt   w@ 0x 17f8000 and not ( any error interrupt )
    and
  while
    tout?
  repeat
  rdrop
  drop
;

( cmd -- cmd )
: command-delay
  dup cmd.delay case
    1 of ." dly:100"  cr  100 delay endof
    2 of ." dly:1000" cr 1000 delay endof
  endcase
;

: done?       0x 00000001 await-interrupt ;
: read-ready? 0x 00000020 await-interrupt ;

( cmd arg -- )
: issue-normal-command
  ." normal command " cr
  2drop
;

( words to from -- )
: wcopy
  begin
    rot ?dup 0>
  while
    -rot 2dup w@ swap w!
    rot 1- -rot
  repeat
  2drop
;

( cmd arg -- )
: send-command-p
  ( todo: check if RCA required, send with RCA )

  ( wait for command inhibit off )
  0x 01 not-busy?

  ." ready to send" cr

  emmc-irpt w@ emmc-irpt w!

  emmc-arg1 w!
  dup cmd.code emmc-cmdtm w!

  command-delay

  done? ." command complete" cr

  ( TODO : switch on cmd.rtype not cmd.rbits then cmd )
  ( todo: handle response types
    rtype-1     1
    rtype-1b    2
    rtype-2i    3
    rtype-2s    4
    rtype-3     5
    rtype-6     6
    rtype-7     7 )
  cmd.rtype case
    1 of
      emmc-resp0 w@
      dup sdcard.status w!
      dup 0x 1e00 and 9 rshift sdcard.card-state w!
      r1-errors-mask and if erbad throw then
    endof
    2 of
      emmc-resp0 w@ dup sdcard.status w!
      0x 1e00 and 9 rshift sdcard.card-state w!
    endof
    3 of
      0 sdcard.status w!
      emmc-resp0 w@ sdcard.cid      w!
      emmc-resp1 w@ sdcard.cid  4 + w!
      emmc-resp2 w@ sdcard.cid  8 + w!
      emmc-resp3 w@ sdcard.cid 12 + w!
    endof
    4 of
      0 sdcard.status w!
      emmc-resp0 w@ sdcard.csd      w!
      emmc-resp1 w@ sdcard.csd  4 + w!
      emmc-resp2 w@ sdcard.csd  8 + w!
      emmc-resp3 w@ sdcard.csd 12 + w!
    endof
    5 of
      0 sdcard.status w!
      emmc-resp0 w@ sdcard.ocr w!
    endof
    6 of
      emmc-resp0 w@ 0x ffff0000 and sdcard.rca w!
      emmc-resp0 w@ 0x 1ffff and
      emmc-resp0 w@ 0x  2000 and 6 lshift rot or ( resp0 bit 13 -> status bit 19 )
      emmc-resp0 w@ 0x  4000 and 8 lshift rot or ( resp0 bit 14 -> status bit 22 )
      emmc-resp0 w@ 0x  8000 and 8 lshift rot or ( resp0 bit 15 -> status bit 23 )
      sdcard.status w!
      emmc-resp0 w@ 0x  1e00 and 9 rshift sdcard.card-state w!
    endof
    7 of
      0 sdcard.status w!
      emmc-resp0 w@
    endof
    ( default case is no response )
  endcase
  ." send-command-p end: " .s
;

( cmd -- )
: send-app-command
  ." send-app-command: rca " sdcard.rca @ .x cr
  sdcard.rca @ ?dup if
    ( rca <> 0, use cmd-app-rca )
    cmd-app-rca swap
  else
    ( rca == 0, use cmd-app )
    cmd-app 0
  then
  send-command-p
;

( cmd -- )
: send-command
  ." send-command: " dup .x cr
  dup cmd.is-app? if send-app-command then
  dup cmd.is-rca? if sdcard.rca @ else 0 then
  send-command-p
;

( cmd arg -- )
: send-command-a
  ." send-command-a: " 2dup .x .x cr
  over cmd.is-app? if send-app-command then
  over cmd.is-rca? if drop sdcard.rca @ then
  send-command-p
;

: emmc-reset-host
  ." emmc-reset-host"
  0 emmc-control0 w!
  0 emmc-control1 w!
  1 24 lshift emmc-control1 w! ( reset host circuit )

  10 delay

  1000000 1 24 lshift emmc-control1 await-clear

  ( enable internal clock and set data timeout )
  0x e 16 lshift emmc-control1 w! ( data timeout unit )
  0x 1           emmc-control1 w! ( clock enable internal )

  10 delay
;

( freq -- divisor )
: get-clock-divisor
  dup 41666667 + 1- swap /              ( 41666667 + freq - 1 / freq )
  dup 0x 3ff > if drop 0x 3ff then
  dup 3 < if drop 4 then
;

( freq -- succ? )
: emmc-set-clock
  1000000 0x 03 emmc-status await-clear

  1 2 emmc-control1 clear-bits!   ( disable clock )
  10 delay

  get-clock-divisor               ( 10 bit clock divisor )
  dup  0x 0ff and 8 lshift        ( lower 8 bits of divisor go in control bits 8..15 )
  swap 0x 300 and 2 rshift        ( high 2 bits of divisor go in control bits 6..7 )
  emmc-control1 w@                ( read control1 )
  0x ffff001f and                 ( clear any old divisor bits )
  or or                           ( set new divisor bits )
  emmc-control1 w!                ( write it back )

  10 delay

  emmc-control1 w@ 0b 0100 or emmc-control1 w! ( set clk_en bit )

  1000000 0b 0010 emmc-control1 await-set
;

: CMD0  cmd-go-idle       swap send-command-a ;
: CMD2  cmd-all-send-cid       send-command ;
: CMD3  cmd-send-rel-addr      send-command ;
: CMD7  cmd-card-select        send-command ;
: CMD8  cmd-send-if-cond  swap send-command-a ;
: CMD9  cmd-send-csd           send-command ;
: CMD41 cmd-send-op-cond  swap send-command-a ;
: CMD51 cmd-send-scr           send-command ;

400000   constant clock-freq-setup
25000000 constant clock-freq-normal

: emmc-reset
  0 sdcard.block-size !
  emmc-reset-host
  clock-freq-setup emmc-set-clock
  emmc-irpt-en   set-all!
  emmc-irpt-mask set-all!

  0 CMD0
;

: check-interface-condition
  ( send voltage range & check pattern, should get same value back )
  0x 01aa CMD8
  dup 0x 01aa <> if ." unusable card: " .x cr efail throw else drop then
;

: check-sdhc-support
  ( check for high capacity )
  ( cmd41 arg is hcs | sdxc_power | voltage )
  0x 54ff8000 CMD41
  sdcard.ocr w@ 0x 40000000 and if 4 else 3 then sdcard.card-type w!
;

: csd-version sdcard.csd 12 + w@ 0x 00c00000 and 22 rshift 1+ ;

: card-size-v1
  ." card-size-v1" cr
  ( get c_size_mult )
  sdcard.csd 8+ w@ 0x 00000380 and 7 rshift ( 39..41 )
  ( 2^(c_size_mult+2) )
  2 + 1 swap lshift

  ( get c_size )
  sdcard.csd 4+ w@ 0x 3 and 10 lshift ( 64..65 )
  sdcard.csd 8+ w@ 0x ffc00000 and 22 rshift or ( 54..63 )
  1+ *

  ( get read_bl_len, use as multiplier )
  sdcard.csd 4+ 0x 0f00 and 8 rshift ( 8..11 )

  *
;

: card-size-v2
  ." card-size-v2" cr
  sdcard.csd 8+ 0x 3fffff00 and 8 rshift
  1+
  512 * 1024 *
;

: csd-format
  sdcard.csd w@ 1 rshift 3 and
;

: check-csd
  CMD9
  dup csd-version case
    1 of card-size-v1 endof
    2 of card-size-v2 endof
    ." unrecognized card version " csd-version .x efail throw
  endcase
  dup sdcard.capacity !
  ." card capacity: " .x cr

  csd-format case
    0 of ." HDD with partition table" cr endof
    1 of ." Floppy with boot sector" cr endof
    2 of ." Universal" cr endof
    3 of ." Unknown/Other" cr endof
  endcase
;

( read n bytes, returns unread remainder)
( a n -- n )
: emmc-read-bytes
  ." emmc-read-bytes" cr
  >r
  ticks 100000 +
  begin
    emmc-status w@ 0x 800 and if  ( read available? )
      emmc-data w@ 2 pick w!      ( read the word, store it )
      swap 4+ swap                ( advance buffer pointer )
      r> 4- >r                    ( decrement remaining )
    then
    rsp@ @ 0>
  while
    tout?
  repeat
  r>                            ( return remaining, may be zero or negative )
;

: read-scr
  ( wait for data inhibit off )
  0x 02 not-busy?

  ( 1 block of 8 bytes )
  0x 10008 emmc-blksizecnt w!

  CMD51

  ." CMD51 complete" cr

  read-ready?

  sdcard.scr 2 emmc-read-bytes

  ." read-scr after read-bytes: " .s

  ." sdcard.scr: " sdcard.scr @ .x cr

  100 delay
;

: emmc-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  0 47 gpio-fsel 47 gpio-pull-up

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  0 sdcard.block-size w!
  0 sdcard.status     w!
  0 sdcard.card-state w!
  0 sdcard.card-type  w!
  0 sdcard.rca        w!
  0 sdcard.ocr        w!
  0 sdcard.csd        w!
  0 sdcard.cid        w!

  ( todo: detect if card absent )

  emmc-reset
  check-interface-condition
  check-sdhc-support
  CMD2
  CMD3
  check-csd
  clock-freq-normal emmc-set-clock
  CMD7
  read-scr
  ." emmc-enable complete" cr
;

: firmware-sets-cdiv?
  ( do a blank set_sdhost_clock, which queries the clock. test word 1 of the reply )
  ~0 ~0 0 0x 38042 tags{{ swap 3-3tag }} 5 msg[] w@ ~0 <>
;

: emmc-device-probe
  cr
  emmc-slotisr-ver w@ dup
  ." Vendor version: " 8 24 rot bits> . cr
  ." SD host specification version: " 8 16 rot bits> case
    0 of ." 1.00 - NOT SUPPORTED" endof
    1 of ." 2.00 - NOT SUPPORTED" endof
    2 of ." 3.00 " endof
    ." not recognized " .
  endcase
  cr
  ." Core clock rate: " clk-emmc clock-rate . cr
  ." Firmware sets cdiv? " firmware-sets-cdiv? if ." Yes" else ." No" then cr
;

sd-old-base base ! hide sd-old-base
echo
