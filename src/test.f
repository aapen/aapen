base @ value test-old-base
hex

(
  Test harness

  The tester defines functions that compare the results of a test with a set of expected
  results. The syntax for each test starts with "t{" followed by a code sequence to test. This is
  followed by "->", the expected results, and "}t". For example, the following:

  t{ 1 1 + -> 2 }t

  tests that one plus one indeed equals two.

 )


variable actual-depth
20 cells allot constant actual-results
variable start-depth
variable error-xt

: error error-xt @ execute ;

\ ( ... -- ) empties the stack
: empty-stack
  depth start-depth @ < if
    depth start-depth @ swap do 0 loop
  then
  depth start-depth @ > if
    depth start-depth @ do drop loop
  then
;

\ ( c-addr u -- ) display an error message
: error1
  tell ." :["                   \ error message
  source tell ." ]" cr          \ show the line that caused the problem
  empty-stack                   \ throw away everything else
;

\ TODO: make ' work while executing
\ ' error1 error-xt !

\ ( -- ) record the pre-test depth
: t{
  depth start-depth !
;

\ ( ... -- ) record depth and contents of stack
: ->
  depth dup actual-depth !
  start-depth @ > if             \ if there is something on the stack
    depth start-depth @ - 0 do   \ save them
      actual-results i cells + !
    loop
  then
;

\ ( ... -- ) compare stack (expected) contents with saved (actual) contents
: }t
  depth actual-depth @ = if
    depth start-depth @ > if
      depth start-depth @ - 0 do
        actual-results i cells + @
        <> if s" incorrect result " error1 unloop exit then
      loop
    then
  else
    s" wrong number of results " error1
  then
;

test-old-base base ! hide test-old-base
