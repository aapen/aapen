# Analyzing the code in <https://github.com/rockytriton/LLD/blob/main/rpi_bm/part13/src/mailbox.c>

`property_data` -> \*u32  (static array of 8192 32-bit words)
`property_buffer` -> struct, memory overlay on `property_data`

tag -> `*mailbox_tag`

layout of `mailbox_tag`

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left">id</td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left"><code>buffer_size</code></td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left"><code>value_length</code></td>
</tr>
</tbody>
</table>

layout of `mailbox_clock`

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left">id</td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left"><code>buffer_size</code></td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left"><code>value_length</code></td>
</tr>

<tr>
<td class="org-right">0c</td>
<td class="org-left"><code>clock_id</code></td>
</tr>

<tr>
<td class="org-right">10</td>
<td class="org-left"><code>clock_rate</code></td>
</tr>
</tbody>
</table>

layout of `property_buffer` struct

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left"><code>size</code></td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left"><code>code</code></td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left"><code>*tags</code></td>
</tr>
</tbody>
</table>

Sequence of activity for a call to `mailbox_process` with a `mailbox_clock` tag:

1.  Called with a `*mailbox_tag` pointing to a `mailbox_clock` struct, and `tag_size` = `sizeof(mailbox_clock)` (5 32-bit words = 20 bytes)
2.  `mailbox_clock` struct copied to `property_data[2]`, resulting in contents of `property_data`:

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">value</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left">undef</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left">undef</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left"><code>RPI_FIRMWARE_GET_CLOCK_RATE</code></td>
<td class="org-left"><code>mailbox_clock.id</code></td>
</tr>

<tr>
<td class="org-right">0c</td>
<td class="org-left">8 (<code>sizeof(mailbox_clock) - sizeof(mailbox_tag))</code></td>
<td class="org-left"><code>mailbox_clock.buffer_size</code></td>
</tr>

<tr>
<td class="org-right">10</td>
<td class="org-left">1</td>
<td class="org-left"><code>mailbox_clock.clock_id</code></td>
</tr>

<tr>
<td class="org-right">14</td>
<td class="org-left">0</td>
<td class="org-left"><code>mailbox_clock.clock_rate</code></td>
</tr>

<tr>
<td class="org-right">&#xa0;</td>
<td class="org-left">&#xa0;</td>
<td class="org-left">&#xa0;</td>
</tr>
</tbody>
</table>

1.  `*property_buffer` points to `property_data[0]` (memory overlay)
2.  `*property_buffer->size` := `tag_size` + 12 (i.e. `sizeof(mailbox_clock) + 12`)
3.  `*property_buffer->code` := `RPI_FIRMWARE_STATUS_REQUEST`, resulting in contents of `property_data`:

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">value</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left">32 (<code>sizeof(mailbox_clock) + 12</code>)</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left">0 (<code>RPI_FIRMWARE_STATUS_REQUEST</code>)</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left">0x00030002 (<code>RPI_FIRMWARE_GET_CLOCK_RATE)</code></td>
<td class="org-left"><code>mailbox_clock.id</code></td>
</tr>

<tr>
<td class="org-right">0c</td>
<td class="org-left">8 (<code>sizeof(mailbox_clock) - sizeof(mailbox_tag))</code></td>
<td class="org-left"><code>mailbox_clock.buffer_size</code></td>
</tr>

<tr>
<td class="org-right">10</td>
<td class="org-left">1 (<code>EMMC</code>)</td>
<td class="org-left"><code>mailbox_clock.clock_id</code></td>
</tr>

<tr>
<td class="org-right">14</td>
<td class="org-left">0</td>
<td class="org-left"><code>mailbox_clock.clock_rate</code></td>
</tr>
</tbody>
</table>

1.  `property_data[(tag_size + 12) / 4 - 1]` := `RPI_FIRMWARE_PROPERTY_END` (index 7 into the u32 array)

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">

<colgroup>
<col  class="org-right" />

<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-right">offset</th>
<th scope="col" class="org-left">value</th>
<th scope="col" class="org-left">field</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-right">00</td>
<td class="org-left">32 (<code>sizeof(mailbox_clock) + 12</code>)</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">04</td>
<td class="org-left">0 (<code>RPI_FIRMWARE_STATUS_REQUEST</code>)</td>
<td class="org-left">&#xa0;</td>
</tr>

<tr>
<td class="org-right">08</td>
<td class="org-left">0x00030002 (<code>RPI_FIRMWARE_GET_CLOCK_RATE)</code></td>
<td class="org-left"><code>mailbox_clock.id</code></td>
</tr>

<tr>
<td class="org-right">0c</td>
<td class="org-left">8 (<code>sizeof(mailbox_clock) - sizeof(mailbox_tag))</code></td>
<td class="org-left"><code>mailbox_clock.buffer_size</code></td>
</tr>

<tr>
<td class="org-right">10</td>
<td class="org-left">1 (<code>EMMC</code>)</td>
<td class="org-left"><code>mailbox_clock.clock_id</code></td>
</tr>

<tr>
<td class="org-right">14</td>
<td class="org-left">0</td>
<td class="org-left"><code>mailbox_clock.clock_rate</code></td>
</tr>

<tr>
<td class="org-right">18</td>
<td class="org-left">???</td>
<td class="org-left">???</td>
</tr>

<tr>
<td class="org-right">1c</td>
<td class="org-left">0 (<code>RPI_FIRMWARE_PROPERTY_END</code>)</td>
<td class="org-left">&#xa0;</td>
</tr>
</tbody>
</table>

1.  `property_data` is cast to (void \*) then to u32 (truncating the address?)
2.  Result is passed to `mailbox_write`, with channel `MAIL_TAGS` (8,
    a.k.a. `property_arm_to_vc`). Lower 4 bits of address are masked out
    and replaced with the channel id.

Mailbox must be in virtual addresses from 00000000 - fffffff0. Must be 16 byte aligned.

1.  VC updates the mailbox tag in place.
2.  `sizeof(mailbox_clock)` bytes are copied back out starting from
    `property_data[2]`. To the caller, it looks like the original structure was updated in place.

<a id="org383b7f5"></a>

# Discrepancies in `LLD/rpi_BM`

The [sample code](https://github.com/raspberrypi/firmware/wiki/Accessing-mailboxes#sample-code) from RPi firmware wiki shows the data being shifted left 4-bits. LLD doesn't do that. Why? (Maybe because it just ignores the return value from `mailbox_read`.)

This [old Linux code](https://github.com/raspberrypi/linux/blob/rpi-3.6.y/arch/arm/mach-bcm2708/vcio.c) does shift the data left before writing and shifts the result right after reading

It looks like LLD puts the `RPI_FIRMWARE_PROPERTY_END` marker one word too late.

<a id="orgc19b44f"></a>

# Addresses as data

See <https://github.com/raspberrypi/firmware/wiki/Accessing-mailboxes#addresses-as-data>

**With the exception of the property tags mailbox channel**, when passing
memory addresses as the data part of a mailbox message, the addresses
should be bus addresses as seen from the VC. These vary depending on
whether the L2 cache is enabled. If it is, physical memory is mapped
to start at 0x40000000 by the VC MMU; if L2 caching is disabled,
physical memory is mapped to start at 0xC0000000 by the VC
MMU. Returned addresses (both those returned in the data part of the
mailbox response and any written into the buffer you passed) will also
be as mapped by the VC MMU. In the exceptional case when you are using
the property tags mailbox channel you should send and receive physical
addresses (the same as you'd see from the ARM before enabling the
MMU).

For example, if you have created a framebuffer description structure
in memory (without having enabled the ARM MMU) at 0x00010000 and you
have not changed config.txt to disable the L2 cache, to send it to
channel 1 you would send 0x40010001 (0x40000000 | 0x00010000 | 0x1) to
the mailbox. Your structure would be updated to include a framebuffer
address starting from 0x40000000 (e.g. 0x4D385000) and you would write
to it using the corresponding ARM physical address (e.g. 0x0D385000).
