noecho

( ARM assembler )

( Utility words that set fields on the instructions. )
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

: set-im19 ( instruction im19 -- instruction )
  0b 1111111111111111111 and	( instruction im19 )
  0d 5 lshift                   ( instruction mask )
  or
;

: set-im16 ( instruction im16 -- instruction )
  0b 1111111111111111 and	( instruction im16 )
  0d 5 lshift                   ( instruction mask )
  or
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

: rt-rn-im9-instruction ( rt rn im9 opcode -- instruction )
  swap set-im9			( rt rn instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: rt-rn-im12-instruction ( rt rn im9 opcode -- instruction )
  swap set-im12			( rt rn instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: rn-instruction ( rn opcode -- instruction )
  swap set-rn			( rn instuction )
;

: rt-rn-instruction ( rt rn opcode -- instruction )
  swap set-rn			( rn instuction )
  swap set-rt			( instruction )
;

: im16-instruction ( im16 opcode -- instruction )
  swap set-im16
;

: rt-im19-instruction ( rt im19 opcode -- instruction )
  swap set-im19			( rt instruction )
  swap set-rt
;

: rt-im21-instruction ( rt im21 opcode -- instruction )
  swap set-im21			( rt instruction )
  swap set-rt
;

( Condition codes used by the b-cond instruction )

: cond-eq 0b 0000 ;
: cond-ne 0b 0001 ;
: cond-cs 0b 0010 ;
: cond-cc 0b 0011 ;
: cond-mi 0b 0100 ;
: cond-pl 0b 0101 ;
: cond-vs 0b 0110 ;
: cond-vc 0b 0111 ;
: cond-hi 0b 1000 ;
: cond-ls 0b 1001 ;
: cond-ge 0b 1010 ;
: cond-lt 0b 1011 ;
: cond-gt 0b 1100 ;
: cond-le 0b 1101 ;
: cond-al 0b 1110 ;
: cond-nv 0b 1111 ;


( Instruction modifiers )

( Turn instruction into the 32 bit version of itself )

: ->32bit ( instruction -- instruction )
  0x 7fffffff and		( clear bit 31 )
;

( Turn on the shift option )

: ->shift ( instruction -- instruction )
  0d 1 0d 22 lshift
  or
;

( Set the condition code for a b-cond instruction )

: ->cond ( instruction cond -- instruction )
  0b 1111 and
  or
;

( Set the preindex option )

: ->pre ( instruction -- instruction )
  0b 11 0d 10 lshift
  or
;

( Set the postindex option )

: ->post ( instruction -- instruction )
  0b 01 0d 10 lshift
  or
;


( These are the actual assembler instructions. )

( Load and store )

: ldur ( rt rn im12 -- instruction ) 0x f8400000 rt-rn-im9-instruction ;
: ldrimm ( rt rn im12 -- instruction ) 0x f9400000 rt-rn-im12-instruction ;

: adr ( rt relative ) 0x 10000000 rt-im21-instruction ;

( Arithmetic )

: addimm ( rt rn im9 -- instruction ) 0x 91000000 rt-rn-im9-instruction ;
: subimm ( rt rn im9 -- instruction ) 0x d1000000 rt-rn-im9-instruction ;

: cbz ( rt im19 -- instruction ) 0x b4000000 rt-im19-instruction ;
: cbnz ( rt im19 -- instruction ) 0x b5000000 rt-im19-instruction ;

: svc ( im16 -- instruction ) 0x d4000001 im16-instruction ;
: hvc ( im16 -- instruction ) 0x d4000002 im16-instruction ;
: smc ( im16 -- instruction ) 0x d4000003 im16-instruction ;
: brkarm64 ( im16 -- instruction ) 0x d4200000 im16-instruction ;
: hlt ( im16 -- instruction ) 0x d4400000 im16-instruction ;
: dcps1 ( im16 -- instruction ) 0x d4a00001 im16-instruction ;
: dcps2 ( im16 -- instruction ) 0x d4a00002 im16-instruction ;
: dcps3 ( im16 -- instruction ) 0x d4a00003 im16-instruction ;

( Branches )

: br ( rn -- instruction ) 0x d61f0000 rn-instruction ;
: blr ( rn -- instruction ) 0x d63f0000 rn-instruction ;
: ret ( rn -- instruction ) 0x d65f0000 rn-instruction ;

: eret ( -- instruction ) 0x d69f03e0 ;
: drps ( -- instruction ) 0x d6bf03e0 ;
 
 ( Conditional branches. The fundimental instruction is b-cond + an
 instruction code. We predefine a few of the common cases. 
 Keep in mind that the jump is relative and multiplied by 4. )

: b-cond ( im19 cond -- instruction )
  0x 54000000			( im19 cond instruction )
  swap ->cond			( im19 instruction )
  swap set-im19		
;

: beq ( im19 -- instruction ) cond-eq b-cond ;
: bne ( im19 -- instruction ) cond-ne b-cond ;
: blt ( im19 -- instruction ) cond-lt b-cond ;
: bgt ( im19 -- instruction ) cond-gt b-cond ;
: ble ( im19 -- instruction ) cond-le b-cond ;
: bge ( im19 -- instruction ) cond-ge b-cond ;


( Create a new primitive word and leave its definition
  open. You *must* complete the word with ;; or it will
  surly crash. )

: defprim
  word create		( Create a new word )
  here @ 8 + ,		( Code word is the next address )
;

( Close out an open primitive word. This is essentially
  the code for next in the assembly. )

: ;;
  0d 0 0d 10 0d 8 ldur ->post w,
  0d 1 0d 0  0d 0 ldur        w,
  0d 1            br          w,
;


( Define a noop primitive. )

defprim do-nothing
;;

echo

