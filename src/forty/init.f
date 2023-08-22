( Some definitions to get us started. )

: star ( -- : Emit a star ) 42 emit ;
: bar ( -- : Emit a bar) star star star star cr ;
: dot ( -- : Emit a dot) star cr ;
: F ( -- : Draw an ascii art F) bar dot bar dot dot ;
: p ( n -- : Print the stop of the stack followed by a newline) . cr ;

F

( Input and output base words )

: base ( n -- : Set the input and output bases.)        dup obase ! ibase ! ;
: hex ( -- : Set the input and output bases to 16.)     16 base ;
: decimal ( -- : Set the input and output bases to 10.) 10 base ;

: field@ + @w wbe ;
: fdt-magic      fdt 0x00 field@ ;
: fdt-totalsize  fdt 0x04 field@ ;
: fdt-struct     fdt 0x08 field@ fdt + ;
: fdt-strings    fdt 0x0c field@ fdt + ;
: fdt-mem-rsvmap fdt 0x10 field@ fdt + ;
: fdt-version    fdt 0x14 field@ ;
: fdt-last-comp  fdt 0x18 field@ ;
: fdt-boot-cpuid fdt 0x1c field@ ;
: fdt-strings-sz fdt 0x20 field@ ;
: fdt-struct-sz  fdt 0x24 field@ ;

(compiling words)

: secondary! (addr -- Make the word a secondary)
  header-func-offset + inner swap !
;

: immediate! ( f addr -- Change the immediate flag of the word at addr to f)
  header-immediate-offset + !
;

( Debugging )

: tron  ( -- : Turn debugging on.) 1 debug ! ;
: troff ( -- : Turn debugging off.)  0 debug ! ;

( Address arithmetic )

: words ( n -- n : Number words -> number bytes ) word * ;
: aligned ( c-addr – a-addr  : Align the address.) word 1 - + word / word * ;

( Testing... )

: even? ( n -- s ) 2 % if "no" else "yes" endif s. cr ;
: countdown hello hello hello while dup 0 > do dup p 1 - done "all done" s. cr ;

: power-of-two ( n -- n ) 
  1 swap 
  while dup 0 > 
  do
    swap 2 * 
    swap 1 -
  done
  drop
;

create by-hand (test word)
  opcode-push-u64 ,
  999 ,
  'p ,
  opcode-stop ,
finish

'by-hand secondary!


