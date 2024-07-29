noecho

( ARM assembler )

( Utility words that set fields on the instructions. )

: set-32bit ( instruction -- instruction )
  0x 3fffffff and		( clear bits 31 and 30)
;

: set-rt ( instruction rt - instruction )
  or
;

: set-rn ( instruction rn -- instruction )
  0d 5 lshift
  or
;

: set-rm ( instruction rm -- instruction )
  0d 16 lshift
  or
;

: set-im21-hi ( instruction im21 -- instruction )
  0d 2 rshift 0d 5 lshift       ( instruction im21-hibits )
  or
;

: set-im21-low ( instruction im21 -- instruction )
  0x 3 and 0d 29 lshift		( instruction im21-lowbits )
  or
;

: set-im21 ( instruction im21 -- instruction )
  dup rot rot			( im21 instruction im21 )
  set-im21-hi			( im21 instruction )
  swap set-im21-low             ( instruction )
;

: set-im12 ( instruction im12 -- instruction )
  0b 111111111111 and		( instruction im12 )
  0d 10 lshift                  ( instruction mask )
  or
;

: set-im9 ( instruction im9 -- instruction )
  0b 111111111 and		( instruction im9 )
  0d 12 lshift                  ( instruction mask )
  or
;

: set-shift ( instruction -- instruction )
  0d 1 0d 22 lshift
  or
;

 
( These are the actual assembler instructions. )

: ldrimm ( rt rn -- instruction )
  0x f9400000			( push the basic opcode )
  swap set-rn			( rt ins )
  swap set-rt			( ins )
;

: adr ( rt relative )
  0x 10000000			( rt relative opcode )
  swap set-im21			( rt instruction )
  swap set-rt
;

: addimm ( rt rn imm9 -- instruction )
  0x 91000000			( rt rn imm12 opcode )
  swap set-im12			( rt rn instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: subimm ( rt rn imm9 -- instruction )
  0x d1000000			( rt rn imm12 opcode )
  swap set-im12			( rt rn instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;


(
  Very rough poc, this word will crash, but if you xray it you will
  see the instructions embedded inside of the definition.
)

: test1
  hello
  hello
  [
  	1  10 addimm w,
  	17 17 ldrimm w,
	30 24 adr w,
  ]
  hello
  hello
;

echo

