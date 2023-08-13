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
