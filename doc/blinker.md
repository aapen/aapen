# Morse code on GPIO LED

On of the strengths of FORTH
is the ease with which you can write low-level code.
This tutorial will show you how to write FORTH code
that controls the ACT/OK LED on the Raspberry Pi.
We will also be using a timer
to control the duration of dots and dashes,
generating [Morse code](http://en.wikipedia.org/wiki/Morse_code).

This code can be entered
(or copy-and-pasted)
directly on the [_pijFORTHos_](/README.md) serial console.
I recommend keeping your FORTH code
in a local file on your host computer,
then copy-and-pasting it into a serial terminal session
to the RPi running _pijFORTHos_.
If you get into trouble,
you can always power-cycle the target RPi
and start over with a fresh environment.

Please note that _pijFORTHos_ **is** case sensitive.
Built-in words and base-16 numbers are all UPPERCASE.
However, many of the new words in this tutorial are defined in lowercase.


## Micro-second Timer

The _pijFORTHos_ startup code initializes the ARM timer
to count at 1Mhz frequency.
The difference between two timer values
tells us the number of microseconds elapsed.
The timer counter is at address 0x2000B420,
so we define a constant giving a name to this address.
We define the FORTH word `us@` to fetch the value at the timer counter address.
~~~
16# 2000B420 CONSTANT ARM_TIMER_CNT

\ us@ ( -- t ) fetch microsecond timer value
: us@ ARM_TIMER_CNT @ ;
~~~
It will be convenient to express elapsed time values
by using three suffix words: `usecs`, `msecs`, and `secs`.
~~~
: usecs ;               \ usecs ( n -- dt ) convert microseconds to timer offset
: msecs 1000 * ;        \ msecs ( n -- dt ) convert milliseconds to timer offset
: secs 1000000 * ;      \ secs ( n -- dt ) convert seconds to timer offset
~~~
We define the FORTH word `us` to busy-wait for a number of microseconds.
The timeout value is calculated as the current time plus the wait time offset.
We keep a copy of this value on the stack for later comparison.
The counter value runs continuously, wrapping around when it overflows.
So, we use signed integer subtraction to determine
the elapsed time between our timeout and "now".
A negative value represents relative "past".
A positive value represents relative "future".
~~~
: us \ ( dt -- ) busy-wait until dt microseconds elapse
        us@ +                   \ timeout = current + dt
        BEGIN
                DUP             \ copy timeout
                us@ -           \ past|future = timeout - current
                0<=             \ loop until not future
        UNTIL
        DROP                    \ drop timeout
;
~~~
You can test the timer code with something like this:
~~~
3 secs us 33 EMIT
~~~
After three seconds you should see '!' on the console (33 is the ASCII code for '!').


## ACT/OK LED control via GPIO

The ACT/OK LED on the RPi is connected to GPIO pin 16.
Function selection bits for pins 10 through 19 are at address 0x20200004.
There are three function selection bits per pin,
so the bits for pin 16 are 0x001C0000,
and 0x00040000 selects the output function.
~~~
16# 20200004 CONSTANT GPFSEL1           \ GPIO function select (pins 10..19)
16# 001C0000 CONSTANT GPIO16_FSEL       \ GPIO pin 16 function select mask
16# 00040000 CONSTANT GPIO16_OUT        \ GPIO pin 16 function is output

GPFSEL1 @               \ read GPIO function selection
GPIO16_FSEL INVERT AND  \ clear function for pin 16
GPIO16_OUT OR           \ set function to output
GPFSEL1 !               \ write GPIO function selection
~~~
GPIO pins are set and cleared by writing to addresses 0x2020001C and 0x20200028 respectively.
Unlike the function selection register,
there is no need to read-modify-write these registers
because they only act on pins for which a bit is set.
The control bit for pin 16 is 0x00010000.
~~~
16# 2020001C CONSTANT GPSET0            \ GPIO pin output set (pins 0..31)
16# 20200028 CONSTANT GPCLR0            \ GPIO pin output clear (pins 0..31)
16# 00010000 CONSTANT GPIO16_PIN        \ GPIO pin 16 set/clear

: +gpio16 GPIO16_PIN GPSET0 ! ; \ set GPIO pin 16
: -gpio16 GPIO16_PIN GPCLR0 ! ; \ clear GPIO pin 16
~~~
Since the LED is active low, it will light up when we **clear** pin 16.
Conversely, we **set** pin 16 to turn the LED off again.
~~~
: LED_ON -gpio16 ;              \ turn on ACT/OK LED (clear 16)
: LED_OFF +gpio16 ;             \ turn off ACT/OK LED (set 16)
~~~
Try out the `LED_ON` and `LED_OFF` words to demonstrate your control of the ACT/OK LED.

## Morse code

[Morse code](http://en.wikipedia.org/wiki/Morse_code)
can be generated in any media that can represent an "on" and "off" state.
Typical examples are a tone, or a light like our LED.
A _character_ is a single dot or dash.
A _letter_ is a series of dot/dashes representing a letter in the alphabet.
A _word_ is a series of letters with extra space in-between
(not to be confused with the FORTH words we're defining).
~~~
: '-' 45 ;                      \ ascii dash character
: '.' 46 ;                      \ ascii dot character

: units 50 msecs * ;            \ units ( n -- dt ) convert dot-units to timer offset
: eoc 1 units us ;              \ end of character
: dit                           \ dot
        '.' EMIT                \       print dot
        LED_ON
        1 units us              \       wait 1 unit time
        LED_OFF
        eoc                     \ end
;
: dah                           \ dash
        '-' EMIT                \       print dash
        LED_ON
        3 units us              \       wait 3 unit times
        LED_OFF
        eoc                     \ end
;
: eol SPACE 2 units us ;        \ end of letter (assumes preceeding eoc)
: ___ eol eol ;                 \ word-break space (assumes preceeding eol)
: _C_ dah dit dah dit eol ;
: _D_ dah dit dit eol ;
: _E_ dit eol ;
: _M_ dah dah eol ;
: _O_ dah dah dah eol ;
: _R_ dit dah dit eol ;
: _S_ dit dit dit eol ;
: _SOS_ dit dit dit dah dah dah dit dit dit eol ;
~~~
Now that we've defined a partial alphabet,
we can compose message by invoking the FORTH words that generate each letter.
~~~
_M_ _O_ _R_ _S_ _E_ ___ _C_ _O_ _D_ _E_
~~~
You should see the ACT/OK LED blinking out Morse code
as the corresponding dots and dashes are printed on the console.
