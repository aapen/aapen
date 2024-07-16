## Layout of a message, in 32-bit words, before sending

```
  +------------------+    Header
  | payload nbytes   |      Length of all tags plus this head and the terminator
  +------------------+
  | 0x00             |      Space for response status
  +------------------+    Tag 1
  | tag id           |      One of the constants that says what to do
  +------------------+
  | value buf nbytes |      How many bytes in the input values
  +------------------+
  | value len nbytes |      How many bytes overall
  +------------------+
  .                  .      Followed by input words
  .                  .
  +------------------+    Tag 2 .. n
  | tag id           |      One of the constants that says what to do
  +------------------+
  | value buf nbytes |      How many bytes in the input values
  +------------------+
  | value len nbytes |      How many bytes overall
  +------------------+
  | 0                |      Sentinel
  +------------------+
```


