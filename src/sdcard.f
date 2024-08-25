noecho
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

peripherals 0x   300000 + constant sd-base
sd-base     0x        0 + constant sd-arg2
sd-base     0x        4 + constant sd-blksizecnt
sd-base     0x        8 + constant sd-arg1
sd-base     0x        c + constant sd-cmdtm
sd-base     0x       10 + constant sd-resp0
sd-base     0x       14 + constant sd-resp1
sd-base     0x       18 + constant sd-resp2
sd-base     0x       1c + constant sd-resp3
sd-base     0x       20 + constant sd-data
sd-base     0x       24 + constant sd-status
sd-base     0x       28 + constant sd-control0
sd-base     0x       2c + constant sd-control1
sd-base     0x       30 + constant sd-irpt
sd-base     0x       34 + constant sd-irpt-mask
sd-base     0x       38 + constant sd-irpt-en
sd-base     0x       3c + constant sd-control2
sd-base     0x       88 + constant sd-tune-step
sd-base     0x       fc + constant sd-slotisr-ver

1 32 lshift 1- constant ~0

: clear-all! 0 swap w! ;
: set-all!  ~0 swap w! ;

( nbits shift v -- v>>shift&1<<bits+1-1 )
: bits> swap rshift 1 rot lshift 1- and ;

( v f shift -- v|f<<shift )
: >bits lshift or ;

( nbits shift v -- v & ~1<<nbits-1 )
: 0bits
  swap rot 1 swap lshift 1-
  swap lshift invert and
;

: cmd          24 lshift ;
: is-data     1 21 >bits ;
: multiblock  1  5 >bits ;
: rbits-48    2 16 >bits ;
: rbits-136   1 16 >bits ;
: rbits-48b   3 16 >bits ;
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
16 cmd rbits-48  rtype-1                                       constant cmd-set-blocklen
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

: .reg tell w@ ." : 0x" %08x ;

: print-sd-status
  cr
  sd-status    s"    status" .reg tab sd-resp0      s"      resp0" .reg tab sd-cmdtm s"     cmdtm" .reg cr
  sd-control0  s"  control0" .reg tab sd-resp1      s"      resp1" .reg tab sd-arg1  s"      arg1" .reg cr
  sd-control1  s"  control1" .reg tab sd-resp2      s"      resp2" .reg tab sd-arg2  s"      arg2" .reg cr
  sd-control2  s"  control2" .reg tab sd-resp3      s"      resp3" .reg cr
  sd-irpt      s"      irpt" .reg tab sd-blksizecnt s" blksizecnt" .reg cr
  sd-irpt-mask s" irpt-mask" .reg cr
  sd-irpt-en   s"   irpt-en" .reg cr
;

( n -- n|throws )
: tout?
  dup ticks <
  if
    ." throwing etout" cr
    print-stack-trace cr
    print-sd-status
    etout throw
  then
;

( micros mask addr -- )
: await-clear
d\  ." await clear:" .s
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
d\  ." await set:" .s
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
variable sdcard.bus-width

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


: matches ( n1 n2 -- n1 b ) over and 0<> ;

( irpt -- )
: await-interrupt
d\  ." await-interrupt: " .s
  >r ( p: 0, r: 1 )
  1000000 ticks +               ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  begin
    sd-irpt w@ rsp@ @ and 0=  ( end-ticks b ) ( p: 0 end-ticks match?, r: 1 )
  while                         ( end-ticks ) ( p: 0 end-ticks, r: 1 )
    tout?                       ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  repeat
  drop

d\  ." irpt observed: " .s

  r> sd-irpt w!               ( clear the interrupt we were waiting for )
  sd-irpt w@

d\  ." irpt observed (cleared): " .s

  0x   10000 matches if print-stack-trace cr etout throw then
  0x  100000 matches if print-stack-trace cr etout throw then
  0x 17f8000 matches if print-stack-trace cr eirpt throw then
  drop

d\  ." after irpt: " .s
;

: done?        0x 00000001 await-interrupt ;
: write-ready? 0x 00000010 await-interrupt ;
: read-ready?  0x 00000020 await-interrupt ;

( inhibit -- )
: not-busy?
d\  ." not-busy? " dup .x cr
  >r
  1000000 ticks +
  begin
    sd-status w@ 0x rsp@ @ and      ( indicated inhibit bit )
    sd-irpt   w@ 0x 17f8000 and not ( any error interrupt )
    and
  while
    tout?
  repeat
  rdrop
  drop
;

( n -- 10^n )
: pow10 1 swap 0 do 10 * loop ;

( cmd -- cmd )
: command-delay dup cmd.delay 1+ pow10 delay-millis ;

( cmd arg -- )
: send-command-p
d\  ." send-command-p: cmd " 2dup swap cmd.index . ." arg " .x cr
  ( wait for command inhibit off )
  0x 01 not-busy?

d\  ." issuing command: " .s

  sd-irpt w@ sd-irpt w!

  sd-arg1 w!
  dup cmd.code sd-cmdtm w!

  command-delay

  done?
d\  ." command complete: " .s

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
      sd-resp0 w@
      dup sdcard.status w!
      dup 0x 1e00 and 9 rshift sdcard.card-state w!
      r1-errors-mask and if erbad throw then
    endof
    2 of
      sd-resp0 w@ dup sdcard.status w!
      0x 1e00 and 9 rshift sdcard.card-state w!
    endof
    3 of
      0 sdcard.status w!
      sd-resp0 w@ sdcard.cid      w!
      sd-resp1 w@ sdcard.cid  4 + w!
      sd-resp2 w@ sdcard.cid  8 + w!
      sd-resp3 w@ sdcard.cid 12 + w!
    endof
    4 of
      0 sdcard.status w!
      sd-resp0 w@ sdcard.csd      w!
      sd-resp1 w@ sdcard.csd  4 + w!
      sd-resp2 w@ sdcard.csd  8 + w!
      sd-resp3 w@ sdcard.csd 12 + w!
    endof
    5 of
      0 sdcard.status w!
      sd-resp0 w@ sdcard.ocr w!
    endof
    6 of
      sd-resp0 w@ 0x ffff0000 and sdcard.rca w!
      sd-resp0 w@ 0x 1ffff and
      sd-resp0 w@ 0x  2000 and 6 lshift rot or ( resp0 bit 13 -> status bit 19 )
      sd-resp0 w@ 0x  4000 and 8 lshift rot or ( resp0 bit 14 -> status bit 22 )
      sd-resp0 w@ 0x  8000 and 8 lshift rot or ( resp0 bit 15 -> status bit 23 )
      sdcard.status w!
      sd-resp0 w@ 0x  1e00 and 9 rshift sdcard.card-state w!
    endof
    7 of
      0 sdcard.status w!
      sd-resp0 w@
    endof
    ( default case is no response )
  endcase
d\  ." send-command-p end: " .s
;

( cmd -- )
: send-app-command
d\  ." send-app-command: rca " sdcard.rca @ .x cr
  sdcard.rca @ ?dup if cmd-app-rca swap else cmd-app 0 then
  send-command-p
;

( cmd -- )
: send-command
d\  ." send-command: cmd " dup cmd.index . cr
  dup cmd.is-app? if send-app-command then
  dup cmd.is-rca? if sdcard.rca @ else 0 then
  send-command-p
;

( cmd arg -- )
: send-command-a
d\  ." send-command-a: cmd " 2dup swap cmd.index . ." arg " .x cr
  over cmd.is-app? if send-app-command then
  over cmd.is-rca? if drop sdcard.rca @ then
  send-command-p
;

: sd-reset-host
d\  ." sd-reset-host" cr
  0 sd-control0 w!
  0 sd-control1 w!
  1 24 lshift sd-control1 w! ( reset host circuit )

  10 delay

  1000000 1 24 lshift sd-control1 await-clear

  ( enable internal clock and set data timeout )
  0x e 16 lshift sd-control1 w! ( data timeout unit )
  0x 1           sd-control1 w! ( clock enable internal )

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
  1000000 0x 03 sd-status await-clear

  sd-control1 w@ 0x fffffffd and sd-control1 w! ( disable clock )
  10 delay

  get-clock-divisor               ( 10 bit clock divisor )
  dup  0x 0ff and 8 lshift        ( lower 8 bits of divisor go in control bits 8..15 )
  swap 0x 300 and 2 rshift        ( high 2 bits of divisor go in control bits 6..7 )
  sd-control1 w@                  ( read control1 )
  0x ffff001f and                 ( clear any old divisor bits )
  or or                           ( set new divisor bits )
  sd-control1 w!                  ( write it back )

  10 delay

  sd-control1 w@ 0b 0100 or sd-control1 w! ( set clk_en bit )

  1000000 0b 0010 sd-control1 await-set
;

: CMD0  cmd-go-idle       swap send-command-a ;
: CMD2  cmd-all-send-cid       send-command ;
: CMD3  cmd-send-rel-addr      send-command ;
: CMD6  cmd-set-bus-width swap send-command-a ;
: CMD7  cmd-card-select        send-command ;
: CMD8  cmd-send-if-cond  swap send-command-a ;
: CMD9  cmd-send-csd           send-command ;
: CMD16 cmd-set-blocklen  swap send-command-a ;
: CMD17 cmd-read-single   swap send-command-a ;
: CMD41 cmd-send-op-cond  swap send-command-a ;
: CMD51 cmd-send-scr           send-command ;

400000   constant clock-freq-setup
25000000 constant clock-freq-normal

: sd-reset
  512 sdcard.block-size !
  sd-reset-host
  clock-freq-setup emmc-set-clock
  sd-irpt-en   set-all!
  sd-irpt-mask set-all!

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
  sdcard.ocr w@ 0x 40000000 and if 4 else 3 then sdcard.card-type !
;

: csd-version
  sdcard.csd 12 + w@ 0x 00c00000 and 22 rshift 1+
;

: card-size-v1
d\  ." card-size-v1: " .s
  ( get c_size_mult )
  sdcard.csd 8+ w@ 0x 00000380 and 7 rshift ( 39..41 )
  ( 2^c_size_mult+2 )
  2 + 1 swap lshift

  ( get c_size )
  sdcard.csd 4+ w@ 0x 3 and 10 lshift ( 64..65 )
  sdcard.csd 8+ w@ 0x ffc00000 and 22 rshift or ( 54..63 )
  1+ *

  ( get read_bl_len, use as multiplier )
  sdcard.csd 4+ 0x 0f00 and 8 rshift ( 8..11 )
  *
d\  ." card-size-v1 end: " .s
;

: card-size-v2
d\  ." card-size-v2" cr
  sdcard.csd 8+ 0x 3fffff00 and 8 rshift
  1+
  512 * 1024 *
;

: csd.format
   1 rshift 3 and
;

: check-csd
d\  ." check-csd: " .s
  CMD9
  csd-version case
    1 of card-size-v1 endof
    2 of card-size-v2 endof
    ." unrecognized card version " csd-version .x efail throw
  endcase
  sdcard.capacity !
d\  ." check-csd end: " .s
;

( read n bytes, returns unread remainder)
( a n -- n )
: sd-read-bytes
d\  ." sd-read-bytes: " .s
  >r
  ticks 100000 +
  begin
    sd-status w@ 0x 800 and if  ( read available? )
      sd-data w@ 2 pick w!      ( read the word, store it )
      swap 4+ swap                ( advance buffer pointer )
      r> 4- >r                    ( decrement remaining )
    then
    rsp@ @ 0>
  while
    tout?
  repeat
  2drop                         ( drop ticks and addr )
  r>                            ( return count of unread bytes, may be zero or negative )
d\  ." sd-read-bytes end: " .s
;

: read-scr
d\  ." read-scr: " .s

  ( wait for data inhibit off )
  0x 02 not-busy?

  ( 1 block of 8 bytes )
  0x 10008 sd-blksizecnt w!

  CMD51

d\  ." CMD51 complete: " .s

  read-ready?

  sdcard.scr 8 sd-read-bytes

d\  ." read-scr after read-bytes: " .s

  dup 0> if ." expected " . ." more bytes " cr efail throw else drop then

d\  ." sdcard.scr: " sdcard.scr @ .x cr

  100 delay
;

: set-bus-width
  sdcard.scr w@ 0x 0100 and 0<> if 1 sdcard.bus-width ! then
  sdcard.scr w@ 0x 0400 and 0<> if 4 sdcard.bus-width ! then

  sdcard.bus-width @ 4 = if
    ( if supported, set 4 bit bus width and update control0 )
    sdcard.rca w@ 2 or CMD6
    sd-control0 w@ 2 or sd-control0 w!
  then
;

: set-block-size
  512 CMD16
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

: card-format-name
  case
    0 of s" HDD with partition table" endof
    1 of s" Floppy with boot sector" endof
    2 of s" Universal" endof
    3 of s" Unknown/Other" endof
  endcase
;

: h@ dup c@ swap 1+ c@ 8 lshift or ;

: c.@+ ( a -- a+1 ) dup c@ %02x  1 + ;
: h.@+ ( a -- a+2 ) dup h@ %04x  2 + ;
: w.@+ ( a -- a+4 ) dup w@ %08x  4 + ;
: q.@+ ( a -- a+8 ) dup  @ %016x 8 + ;

: sd-report
  cr
  ." SD card report" cr
  ." ==============" cr
  ." Card type: "  sdcard.card-type @ .d cr
  ." Capacity: "   sdcard.capacity @ .d cr
  ." Format: "     sdcard.csd w@ csd.format card-format-name tell cr
  ." Card state: " sdcard.card-state @ card-state-name tell cr
  base @ >r hex
  ." RCA: 0x" sdcard.rca q.@+ cr drop
  ." OCR: 0x" sdcard.ocr q.@+ cr drop
  ." SCR: 0x" sdcard.scr q.@+ cr drop
  ." CID: 0x" sdcard.cid q.@+ q.@+ cr drop
  ." CSD: 0x" sdcard.csd q.@+ q.@+ cr drop
  r> base !
;

: sd-enable
  0 34 gpio-fsel 0 35 gpio-fsel 0 36 gpio-fsel 0 37 gpio-fsel 0 38 gpio-fsel
  0 39 gpio-fsel

  0 47 gpio-fsel 47 gpio-pull-up

  7 48 gpio-fsel 7 49 gpio-fsel 7 50 gpio-fsel 7 51 gpio-fsel 7 52 gpio-fsel

  0 sdcard.card-type  !
  0 sdcard.block-size !
  0 sdcard.status     !
  0 sdcard.card-state !
  0 sdcard.rca        !
  0 sdcard.ocr        !
  0 sdcard.csd        !
  0 sdcard.cid        !
  0 sdcard.bus-width  !

  ( todo: detect if card absent )

  sd-reset                          100 delay-millis
  check-interface-condition         100 delay-millis
  check-sdhc-support                100 delay-millis
  CMD2                              100 delay-millis
  CMD3                              100 delay-millis
  check-csd                         100 delay-millis
  clock-freq-normal emmc-set-clock  100 delay-millis
  CMD7                              100 delay-millis
  read-scr                          100 delay-millis
  set-bus-width                     100 delay-millis
  set-block-size                    100 delay-millis

  sd-report
d\  ." emmc-enable complete" cr
;

: firmware-sets-cdiv?
  ( do a blank set_sdhost_clock, which queries the clock. test word 1 of the reply )
  ~0 ~0 0 0x 38042 tags{{ swap 3-3tag }} 5 msg[] w@ ~0 <>
;

: sd-device-probe
  cr
  sd-slotisr-ver w@ dup
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

: card-type-2-hc? sdcard.card-type @ 4 = ;

( a-buf a-card -- )
: sd-read-block
d\  ." sd-read-block: card-addr " 2dup .x ."  into " .x cr
  0x 02 not-busy?

  ( HC uses addr / 512, others just addr )
d\  card-type-2-hc? if 9 rshift then

d\  ." sd-read-block: send CMD17" cr
  ( blksizecnt <- 1 block << 16 | 512 blocksize )
  1 16 lshift sdcard.block-size @ or sd-blksizecnt w!

  CMD17
d\  ." sd-read-block: cmd sent" cr
  read-ready?
d\  ." sd-read-block: read ready." cr
  512 sd-read-bytes
d\  ." sd-read-block: bytes remaining " dup . cr

  dup 0> if ." expected " . ." more bytes " cr efail throw else drop then
;

: blocks sdcard.block-size @ * + ;

( a-buf a-card nblks -- a-buf' a-card' )
: sd-read-blocks
  0 do
    over i blocks
    over i blocks
    .s
    sd-read-block
  loop
  2drop
;

(
        PARTITION TABLE ----------------------------------------------------------------------
)

( reserve space for reading blocks )
128 cells allot constant sdbuf

( reserve space to hold partition table )
16 cells allot constant partitions
0 value active-partition

: part[] 16 * partitions + ;

: bs?  sdbuf dup c@ 0x eb = swap 1+ c@ 0x e9 = or ;
: mbr? sdbuf 508 + w@ 0x aa550000 = ;
: gpt? sdbuf 512 +  @ 0x 00005452415020494645 = ;

: ppart-bs
;

: mount-bs
;

( n -- b )
: part-active? part[] c@ 0x 80 = ;

( n -- )
: part-info
  base @ >r hex
  part[]
  c.@+ space                            ( status )
  c.@+ space                            ( head start )
  h.@+ space                            ( cyl & sect start )
  c.@+ space                            ( part type )
  c.@+ space                            ( head end )
  h.@+ space                            ( cyl & sect end )
  w.@+ space                            ( first sector )
  w.@+ space                            ( sectors total )
  r> base !
;

( a -- )
: ppart-mbr
  cr
  ." MBR partition table" cr
  ." # A? HS CSTR TP HE CEND FRSTSECT TOTLSECT" cr
  4 0 do
    i part-active? if
      i 1 u.r space
      i part-info
      cr
    then
  loop
  cr
;

( -- )
: mount-mbr
  mbr? if
    sdbuf 446 + partitions 64 cmove       ( copy partition table )
  then
;

: ppart-gpt
  ." gpt" cr
;

: mount-gpt
  ." mount-gpt" cr
;

( -- n )
: partition-type
  gpt? if 1 else
  mbr? if 2 else
  bs?  if 0 else
  -1 then then then
;

: mount
  sdbuf 0 2 sd-read-blocks
  partition-type case
    0 of mount-bs  ppart-bs  cr endof
    1 of mount-gpt ppart-gpt cr endof
    2 of mount-mbr ppart-mbr cr endof
    ." no partition table??" cr efail throw
  endcase
;

sd-old-base base ! hide sd-old-base
echo
