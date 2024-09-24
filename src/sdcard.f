base @ value sd-old-base
decimal

peripherals  0x200000 +
reg gpio-fsel0  reg gpio-fsel1   reg  gpio-fsel2 reg gpio-fsel3 reg gpio-fsel4 reg gpio-fsel5 res0
reg gpio-set0   reg gpio-set1    res0
reg gpio-clr0   reg gpio-clr1    res0 res0
reg gpio-lev0   reg gpio-lev1    res0
reg gpio-eds0   reg gpio-eds1    res0
reg gpio-ren0   reg gpio-ren1    res0
reg gpio-fen0   reg gpio-fen1    res0
reg gpio-hen0   reg gpio-hen1    res0
reg gpio-len0   reg gpio-len1    res0
reg gpio-paren0 reg gpio-paren1  res0
reg gpio-afen0  reg gpio-afen1   res0
reg gpio-pud    reg gpio-pudclk0 reg  gpio-pudclk1
drop

peripherals  0x300000 +
reg sd-arg2 reg sd-blksizecnt reg sd-arg1 reg sd-cmdtm reg sd-resp0 reg sd-resp1 reg sd-resp2 reg sd-resp3 reg sd-data reg sd-status reg sd-control0 reg sd-control1 reg sd-irpt reg sd-irpt-mask reg sd-irpt-en reg sd-control2 drop
sd-arg2 0x88 + reg sd-tune-step drop
sd-arg2 0xfc + reg sd-slotisr-ver drop

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

: cmd.is-app?  0x800000000 and 0<> ;
: cmd.is-rca?  0x100000000 and 0<> ;
: cmd.is-data?    0x200000 and 0<> ;
: cmd.code      0xffffffff and ;
: cmd.index    24 rshift 0x3f and ;
: cmd.delay    33 rshift 0x3 and ;
: cmd.rbits    16 rshift 0x3 and ;
: cmd.rtype    36 rshift 0x7 and ;

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

0xff9c004 constant r1-errors-mask

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
  rot ticks + -rot
  begin
    dup w@ 2 pick
    and 0=
  while
    rot tout? -rot
  repeat
  drop drop drop
;

variable sdcard.csd 2 cells allot
variable sdcard.cid 2 cells allot
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
  >r ( p: 0, r: 1 )
  1000000 ticks +               ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  begin
    sd-irpt w@ rsp@ @ and 0=  ( end-ticks b ) ( p: 0 end-ticks match?, r: 1 )
  while                         ( end-ticks ) ( p: 0 end-ticks, r: 1 )
    tout?                       ( end-ticks ) ( p: 0 end-ticks, r: 1 )
  repeat
  drop


  r> sd-irpt w!               ( clear the interrupt we were waiting for )
  sd-irpt w@


  0x10000   matches if print-stack-trace cr etout throw then
  0x100000  matches if print-stack-trace cr etout throw then
  0x17f8000 matches if print-stack-trace cr eirpt throw then
  drop

;

: done?        0x00000001 await-interrupt ;
: write-ready? 0x00000010 await-interrupt ;
: read-ready?  0x00000020 await-interrupt ;

: rpeek rsp@ @ ;

( inhibit -- )
: not-busy?
  >r
  1000000 ticks +
  begin
    sd-status w@ rpeek and         ( indicated inhibit bit )
    sd-irpt   w@ 0x17f8000 and not ( any error interrupt )
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
  ( wait for command inhibit off )
  0x01 not-busy?


  sd-irpt w@ sd-irpt w!

  sd-arg1 w!
  dup cmd.code sd-cmdtm w!

  command-delay

  done?

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
      dup 0x1e00 and 9 rshift sdcard.card-state w!
      r1-errors-mask and if erbad throw then
    endof
    2 of
      sd-resp0 w@ dup sdcard.status w!
      0x1e00 and 9 rshift sdcard.card-state w!
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
      sd-resp0 w@ 0xffff0000 and sdcard.rca w!
      sd-resp0 w@ 0x1ffff and
      sd-resp0 w@ 0x2000 and 6 lshift rot or ( resp0 bit 13 -> status bit 19 )
      sd-resp0 w@ 0x4000 and 8 lshift rot or ( resp0 bit 14 -> status bit 22 )
      sd-resp0 w@ 0x8000 and 8 lshift rot or ( resp0 bit 15 -> status bit 23 )
      sdcard.status w!
      sd-resp0 w@ 0x1e00 and 9 rshift sdcard.card-state w!
    endof
    7 of
      0 sdcard.status w!
      sd-resp0 w@
    endof
    ( default case is no response )
  endcase
;

( cmd -- )
: send-app-command
  sdcard.rca @ ?dup if cmd-app-rca swap else cmd-app 0 then
  send-command-p
;

( cmd -- )
: send-command
  dup cmd.is-app? if send-app-command then
  dup cmd.is-rca? if sdcard.rca @ else 0 then
  send-command-p
;

( cmd arg -- )
: send-command-a
  over cmd.is-app? if send-app-command then
  over cmd.is-rca? if drop sdcard.rca @ then
  send-command-p
;

: sd-reset-host
  0 sd-control0 w!
  0 sd-control1 w!
  1 24 lshift sd-control1 w! ( reset host circuit )

  10 delay

  1000000 1 24 lshift sd-control1 await-clear

  ( enable internal clock and set data timeout )
  0xe 16 lshift sd-control1 w! ( data timeout unit )
  0x1           sd-control1 w! ( clock enable internal )

  10 delay
;

( freq -- divisor )
: get-clock-divisor
  dup 41666667 + 1- swap /              ( 41666667 + freq - 1 / freq )
  dup 0x3ff > if drop 0x3ff then
  dup 3 < if drop 4 then
;

( freq -- succ? )
: emmc-set-clock
  1000000 0x03 sd-status await-clear

  sd-control1 w@ 0xfffffffd and sd-control1 w! ( disable clock )
  10 delay

  get-clock-divisor               ( 10 bit clock divisor )
  dup  0x0ff and 8 lshift        ( lower 8 bits of divisor go in control bits 8..15 )
  swap 0x300 and 2 rshift        ( high 2 bits of divisor go in control bits 6..7 )
  sd-control1 w@                  ( read control1 )
  0xffff001f and                 ( clear any old divisor bits )
  or or                           ( set new divisor bits )
  sd-control1 w!                  ( write it back )

  10 delay

  sd-control1 w@ 0b0100 or sd-control1 w! ( set clk_en bit )

  1000000 0b0010 sd-control1 await-set
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
  0x01aa CMD8
  dup 0x01aa <> if ." unusable card: " .x cr efail throw else drop then
;

: check-sdhc-support
  ( check for high capacity )
  ( cmd41 arg is hcs | sdxc_power | voltage )
  0x54ff8000 CMD41
  sdcard.ocr w@ 0x40000000 and if 4 else 3 then sdcard.card-type !
;

: csd-version
  sdcard.csd 12 + w@ 0x00c00000 and 22 rshift 1+
;

: card-size-v1
  ( get c_size_mult )
  sdcard.csd 8+ w@ 0x00000380 and 7 rshift ( 39..41 )
  ( 2^c_size_mult+2 )
  2 + 1 swap lshift

  ( get c_size )
  sdcard.csd 4+ w@ 0x3 and 10 lshift ( 64..65 )
  sdcard.csd 8+ w@ 0xffc00000 and 22 rshift or ( 54..63 )
  1+ *

  ( get read_bl_len, use as multiplier )
  sdcard.csd 4+ 0x0f00 and 8 rshift ( 8..11 )
  *
;

: card-size-v2
  sdcard.csd 8+ 0x3fffff00 and 8 rshift
  1+
  512 * 1024 *
;

: csd.format
   1 rshift 3 and
;

: check-csd
  CMD9
  csd-version case
    1 of card-size-v1 endof
    2 of card-size-v2 endof
    ." unrecognized card version " csd-version .x efail throw
  endcase
  sdcard.capacity !
;

( read n bytes, returns unread remainder)
( a n -- n )
: sd-read-bytes
  >r
  ticks 1000000 +
  begin
    sd-status w@ 0x800 and if           ( read available? )
      sd-data w@ 2 pick w!              ( read the word, store it )
      swap 4+ swap                      ( advance buffer pointer )
      r> 4- >r                          ( decrement remaining )
    then
    rsp@ @ 0>
  while
    tout?
  repeat
  2drop                         ( drop ticks and addr )
  r>                            ( return count of unread bytes, may be zero or negative )
;

: read-scr

  ( wait for data inhibit off )
  0x02 not-busy?

  ( 1 block of 8 bytes )
  0x10008 sd-blksizecnt w!

  CMD51


  read-ready?

  sdcard.scr 8 sd-read-bytes


  dup 0> if ." expected " . ." more bytes " cr efail throw else drop then


  100 delay
;

: set-bus-width
  sdcard.scr w@ 0x0100 and 0<> if 1 sdcard.bus-width ! then
  sdcard.scr w@ 0x0400 and 0<> if 4 sdcard.bus-width ! then

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

( hex print value at addr and step addr )
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
;

: firmware-sets-cdiv?
  ( do a blank set_sdhost_clock, which queries the clock. test word 1 of the reply )
  ~0 ~0 0 0x38042 tags{{ swap 3-3tag }} 5 msg[] w@ ~0 <>
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
\  2dup ." reading block at " .x ." into memory at " .x cr

  0x02 not-busy?

  ( HC uses addr / 512, others just addr )

  ( blksizecnt <- 1 block << 16 | 512 blocksize )
  1 16 lshift sdcard.block-size @ or sd-blksizecnt w!

  CMD17
  read-ready?
  512 sd-read-bytes

  dup 0> if ." expected " . ." more bytes " cr efail throw else drop then
;

: blocks  sdcard.block-size @ * ;
: blocks+ blocks + ;

( a-buf a-card nblks -- a-buf' a-card' )
: sd-read-blocks
  0 do
    over i blocks+
    over i blocks+
    sd-read-block
  loop
  2drop
;

(
	FILE SYSTEM INTERFACE --------------------------------------------------------------
)

variable curdir
0 curdir !

(

	PARTITION VARIABLES ----------------------------------------------------------------

)

variable mounted 2 cells allot

0
1 +field -.status
1 +field -.head-start
2 +field -.cyl-start
1 +field -.type
1 +field -.head-end
2 +field -.cyl-end
4 +field -.sector
4 +field -.sectors
constant ptentry%

( reserve space to hold partition table )
ptentry% 4 []buffer ptable

(
        FAT 12/16/23  ----------------------------------------------------------------------
)

0
3 +field -.bs-jmpboot            \ 0..2
8 +field -.bs-oemname            \ 3..10
2 +field -.bytes-per-sector      \ 11..12
1 +field -.sectors-per-cluster   \ 13
2 +field -.reserved-sector-count \ 14..15
1 +field -.num-fats              \ 16
2 +field -.root-entry-count      \ 17..18
2 +field -.total-sectors16       \ 19..20
1 +field -.media                 \ 21
2 +field -.fat-size16            \ 22..23
2 +field -.sectors-per-track     \ 24..25
2 +field -.num-heads             \ 26..27
4 +field -.hidden-sectors        \ 28..31
4 +field -.total-sectors32       \ 32..35
constant fat-bpb%

( fat32 specific part that follows fat-bpb% )
fat-bpb%
4 +field -.fat32-size            \ 36..39
2 +field -.fat32-ext-flags       \ 40..41
2 +field -.fat32-fsversion       \ 42..43
4 +field -.fat32-root-cluster    \ 44..47
2 +field -.fat32-fsinfo          \ 48..49
2 +field -.fat32-bk-boot-sec     \ 50..51
12 +field -.fat32-reserved-0     \ 52..63
1 +field -.fat32-drv-nbr         \ 64
1 +field -.fat32-reserved-1      \ 65
1 +field -.fat32-boot-sig        \ 66
4 +field -.fat32-volume-id       \ 67..70
11 +field -.fat32-volume-label   \ 71..81
8 +field -.fat32-fs-type         \ 82..89
constant fat-bpb-f32-ext%

0
11 +field -.sfn-name
1  +field -.attrib
1  +field -.nt-reserved
1  +field -.time-tenth
2  +field -.write-time
2  +field -.write-date
2  +field -.last-access-date
2  +field -.first-cluster-hi
2  +field -.create-time
2  +field -.create-date
2  +field -.first-cluster-lo
4  +field -.file-size
constant dirent-sfn%

0
1  +field -.ldir-seq-num
10 +field -.ldir-name1
1  +field -.ldir-attr
1  +field -.ldir-type
1  +field -.ldir-chksum
12 +field -.ldir-name2
2  +field -.ldir-first-cluster-lo
4  +field -.ldir_name3
constant dirent-lfn%

( align HERE to 16 byte boundary )
here @ 15 + 15 invert and here !
4 256 []buffer fatbuf
variable bbuf 128 cells allot
variable bytes-per-sector
variable reserved-sector-count
variable first-fat-sector
variable first-data-sector
variable data-sectors
variable sectors-per-cluster
variable root-cluster
variable total-clusters

( unaligned access to 32 bit value )
( addr -- n )
: w@un
  here @ aligned ( addr addr' )
  dup >r         ( addr addr' | r: addr' )
  4 cmove        ( | r: addr' | byte copy to aligned temp space )
  r> w@          ( n | r: | then read as a word )
;

: cd/  root-cluster @ curdir ! ;

: fat-info
  bbuf mounted @ blocks 1 sd-read-blocks

  bbuf -.bytes-per-sector h@ bytes-per-sector !
  bbuf -.sectors-per-cluster c@ sectors-per-cluster !
  bbuf -.reserved-sector-count h@ reserved-sector-count !

  bbuf -.fat-size16 h@ 0=
  bbuf -.root-entry-count h@ 0=
  and if
    bbuf -.fat32-root-cluster w@
    root-cluster !

    cd/

    bbuf -.reserved-sector-count h@
    bbuf -.hidden-sectors w@ +
    dup
    first-fat-sector !

    bbuf -.fat32-size w@
    bbuf -.num-fats c@ * +
    dup
    first-data-sector !

    bbuf -.total-sectors32 w@
    swap -
    data-sectors !

    ."    FAT32 volume label: " bbuf -.fat32-volume-label 11 tell cr
    ."       FAT32 volume id: " bbuf -.fat32-volume-id w@un .x cr
  else
    ." maybe fat16" cr -5 abort
  then

  data-sectors @ sectors-per-cluster @ / total-clusters !
  ."      first fat sector: " first-fat-sector @ . cr
  ."     first data sector: " first-data-sector @ . cr
  ."          data sectors: " data-sectors @ . cr
  ."      bytes per sector: " bytes-per-sector @ . cr
  ."   sectors per cluster: " sectors-per-cluster @ . cr
  ." reserved sector count: " reserved-sector-count @ . cr
  ."        total clusters: " total-clusters @ . cr
  ."          root cluster: " root-cluster @ . cr
;

( n_entry -- n_sector)
: fat-sector          128 / first-fat-sector @ + ;
: fat-entry-in-sector 128 mod ;

( this is horribly inefficient and will cause many re-reads of the sectors )
( n_entry -- u )
: fat@
  dup fat-sector
  0 fatbuf swap                         ( we will read the fat entry's sector into temp space )
  blocks                                ( get the card address )
  sd-read-block                         ( read the table )
  fat-entry-in-sector                   ( index of FAT entry )
  fatbuf                                ( addr of FAT entry )
  w@
;

: fat-end? ( n -- flg ) 0x0ffffff8 >= ;
: cluster-first-sector ( n -- n ) 2 - sectors-per-cluster @ * first-data-sector @ + ;

: next-cluster ( cluster -- )
  dup cluster-first-sector blocks bbuf swap sectors-per-cluster @
  sd-read-blocks
  fat@
;

: root    ( -- cluster# ) root-cluster @ next-cluster ;
: dirent  ( n -- addr )   dirent-sfn% * bbuf + ;
: lfn?    ( n -- flg )    -.attrib c@ 0xf = ;
: free?   ( n -- flg )    c@ 0xe5 = ;
: last?   ( n -- flg )    c@ 0x00 = ;
: subdir? ( n -- flg )    -.attrib c@ 0x10 and 0<> ;

: first-cluster
  dup  -.first-cluster-hi h@ 16 lshift
  swap -.first-cluster-lo h@ or
;

\ : c@c!+ ( c-addr1 c-addr2 -- c-addr1+ c-addr2+ )
\   2dup c@ swap c! 1+ swap 1+ swap
\ ;

\ : dfn ( dest-addr src-addr -- )
\   8 0 do c@c!+ loop
\   swap '.' over c! 1+ swap
\   3 0 do c@c!+ loop
\   2drop
\ ;

: 8.3 ( addr -- )
  8 0 do dup c@ emit 1+ loop
  '.' emit
  3 0 do dup c@ emit 1+ loop
  drop
;

: .dirent ( addr -- )
  dup free? if drop exit then
  dup lfn?  if drop exit then

  dup first-cluster %08x space
  dup subdir? if ." <dir> " else ."       " then
  dup -.file-size w@ %08x space
  8.3
  cr
;

variable dirwalk-cur-cluster
variable dirwalk-cur-index
variable dirwalk-saw-last?

: dirwalk-continue?
  dirwalk-cur-cluster @ dup fat-end? not swap 0> and
  dirwalk-saw-last? @ not and
;

: dirwalk-next-block
  dirwalk-cur-cluster @
  dup fat-end? if 0 else next-cluster then
  -1 dirwalk-cur-index !
  dup dirwalk-cur-cluster !
;

: dirwalk-start ( cluster -- )
  dirwalk-cur-cluster !
  0 dirwalk-saw-last? !
  dirwalk-next-block drop
;

: dirwalk-need-next-block? dirwalk-cur-index @ 16 >= ;

( return addr of next dirent or 0 if done )
: dirwalk-next-entry
  dirwalk-cur-index @ 1+ dirwalk-cur-index !
  dirwalk-need-next-block? if
    dirwalk-next-block 0= if 0 exit then
    0 dirwalk-cur-index !
  then
  dirwalk-cur-index @ dirent
  dup last? if 1 dirwalk-saw-last? ! drop 0 then
;

: dirwalk-end
  0 dirwalk-cur-cluster !
  -1 dirwalk-cur-index !
;

: dir
  ." CLUSTER  DIR?  SIZE     NAME" cr
  curdir @ dirwalk-start
  begin dirwalk-next-entry dup while
    .dirent
  repeat
  drop
  ." <end>" cr
  dirwalk-end
;

: dir/ curdir @ cd/ dir curdir ! ;

( In curdir, find file matching string. Put first cluster in TOS if )
( found, -1 otherwise. )
: find-file ( c-addr u -- u )
  curdir @ dirwalk-start
  begin
    dirwalk-next-entry dup              ( c-addr u i i )
  while                                 ( c-addr u i )
    >r 2dup r>                          ( c-addr u c-addr u dirent )
    0d11                                ( c-addr u c-addr u dirent 11 )
    compare                             ( c-addr u cmp )
    0= if
      2drop
      dirwalk-cur-index @ dirent first-cluster
      exit
    then
  repeat
  dirwalk-end                           ( c-addr u )
  2drop -1
;

: cd
  '"' parse find-file
  dup 0< if ." not found" cr exit then
  dup 0= if drop root-cluster @ then    ( special case for .. from first-level directory )
  curdir !
;

(
        PARTITION TABLE ----------------------------------------------------------------------
)

: bs?  bbuf dup   c@ 0xeb = swap 1+ c@ 0xe9 = or ;
: mbr? bbuf 508 + w@ 0xaa550000 = ;
: gpt? bbuf 512 +  @ 0x00005452415020494645 = ;

( n -- b )
: active? ptable -.status  c@ 0x80 = ;
: fat?    ptable -.type    c@ 0x0b = ;
: sector  ptable -.sector  h@ ;
: sectors ptable -.sectors h@ ;

( n -- )
: .ptentry
  dup . space
  ptable
  c.@+ space c.@+ space h.@+ space c.@+ space c.@+ space h.@+ space w.@+ space w.@+ cr
  drop
;

( a -- )
: ppart-mbr
  cr
  ." MBR partition table" cr
  ." # A? HS CSTR TP HE CEND FRSTSECT TOTLSECT" cr
  4 0 do
    i active? if i .ptentry then
  loop cr
;

: mount-mbr ( -- )
  bbuf 446 + 0 ptable 64 cmove
  4 0 do
    i dup active? swap fat? and if
      i dup sectors swap sector mounted 2!
      ." mounting partition " i . cr
      fat-info
      unloop exit
    then
  loop
;

: mount
  bbuf 0 2 sd-read-blocks
  bs?  if ." boot sector disks are not supported" abort else
  gpt? if ." gpt partitioned disks are not supported" abort else
  mbr? if mount-mbr else
  ." partition table??" efail throw
  then then then
;

sd-old-base base ! hide sd-old-base
