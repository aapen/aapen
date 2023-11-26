# Frame Buffer Graphics

## Coordinates

Top left is (0, 0)

Bottom right is (1023, 767)

Coordinates address the center of each pixel.

Coordinates are integers. We do not support subpixel addressing.

## Initialization

To get a frame buffer pointer, and to have it displayed on the screen,
we use the Mailbox interface. This means we have to ask the GPU to
pretty please give us a frame buffer.

If that operation fails we're pretty much dead in the water. The UART
should still work but absolutely nothing can be displayed on screen.

## Frame Buffer Access

We use 8-bit depth. Each pixel is an index into a color
palette. Therefore a pixel is a u8 and the frame buffer appears as an
array of u8. (In Zig terms, it is a `[*]u8`. Forty can directly peek
and poke the frame buffer.

To get the frame buffer address in Forty, use `[[ fb FrameBuffer.base
+]]`. The size of the frame buffer is `[[ fb FrameBuffer.buffer_size
+]]`.

Other useful struct members:

- FrameBuffer.pitch:: The number of pixels per row.
- FrameBuffer.palette:: Pointer to `[256]u32` that defines the palette

## Line Drawing

We use Bresenham's algorithm. No antialiasing because we _like_ the
Moire effect.

If the line is exactly vertical or exactly horizontal, we use faster
versions of drawing that only have a loop with addition instead of the
full Bresenham.

The inner loop directly accesses frame buffer memory, there is no need
to go through a separate "drawPixel" function.

We address a pixel as an array index into the frame buffer (treated as
an u8 array).

We are not anti-aliasing lines, since we have a palette based color scheme

## Fill

We use DMA for fast filling. We set the DMA request's destination to
walk through the target region, while setting the source to a single
address and turning off the source increment field. This has the
effect of advancing the target pointer on every transfer while keeping
the source fixed.

The source points to a vector of 16 copies of the desired color, this
lets the DMA engine run at its maximum speed of 128 bits per transfer.

If the target region is the entire width of the screen, then the rows
will be contiguous. In that case, we set up the DMA request as a
1-dimensional (linear) transfer that loops over all pixels. If the
target region is not the full width of the screen then we use a 2-D
transfer with slightly more complicated setup.

If DMA is not available for some reason (maybe all DMA channels are
occupied) then we fall back to a CPU loop over the target region.

We also use the DMA fill operation to clear the screen or clear a
region. In this case "clear" really just means to fill the pixels with
the current background color.

## Text

We have a fixed font embedded at compile time from the file
`data/character_rom.bin`. The font is assumed to be 8x16
pixels. (These dimensions are hardcoded in many places.)

Zig's `@embedFile` builtin creates a `[*]u8`. It's more convenient for
us to have the font as an array of `@Vector(8, bool)` values. To keep
startup time fast, we do that conversion at comptime.

When drawing a character on the screen, we use vector operations to go
from the single-bit font definition to a row with the foreground &
background colors to put into the frame buffer. This works using Zig's
`@select` builtin, which applies an element-by-element test and picks
one of two source vectors' elements to create the output vector. One
source vector is a splat of the foreground color, the other is a splat
of the background. Using a row of the character data (the `@Vector(8,
bool)` from comptime) as the selection value, we get back a vector
that has the background color wherever the character rom had a 0 and
the foreground color wherever it had a 1.

At that point, we can assign the resulting vector directly to an
address in the frame buffer. Zig will generate vectorized code that
has the ARM CPU doing big transfers (128 bits at a time) to memory.

Since we are doing an entire row of the character at a time, we only
need to loop over the rows, adding the frame buffer's pitch to the
target pointer for each row.

The result is a frame buffer operation that uses only addition and
vectorized arithmetic operations with no branches.
