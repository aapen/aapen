\ test cases drawn from https://forth-standard.org

hex

.\ 6.1.0690	abs
t{  0 abs -> 0 }t
t{  1 abs -> 1 }t
t{ -1 abs -> 1 }t

.\ 6.1.2165	s-quote
t{ : gc4 s" XY" ; -> }t
t{ gc4 swap drop -> 2 }t
t{ gc4 drop dup c@ swap char+ c@ -> 58 59 }t
: gc5 s" A string"2drop ; \ there is no space between the " and 2drop
t{ gc5 -> }t

cr
