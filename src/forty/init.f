( Some definitions to get us started. )

: star ( Emit a star ) 42 emit ;
: bar star star star star cr ;
: dot star cr ;
: F bar dot bar dot dot ;
: p . cr ;

F

( Input and output base words )

: base ( n -- ) dup obase ! ibase ! ;
: hex ( -- ) 16 base ;
: decimal ( -- ) 10 base ;

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


( Debugging )

: tron 1 debug ! ;
: troff 0 debug ! ;
