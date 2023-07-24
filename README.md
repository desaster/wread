# DOS CLI for reading raw sectors from a hard disk

A very crude CLI program for reading hard drive sectors using INT 13H and
dumping the contents on screen.

This program was intended to be used for imaging a hard drive of a DEC Rainbow
100 computer over serial connection. In it's current state it may however be
too slow for that.

## Usage

The CLI accepts a few single character commands:

| Cmd | Parameters | Description |
| --- | --- | --- |
| `q` | | Quits the program |
| `a` | `c<value> h<value> s<value>` | assigns cyl/head/sector values for next read |
| `r` | | Reads a raw sector into memory using the previously assigned C/H/S. Displays status, 00 = Success |
| `d` | | Dumps entire sector of 512 bytes to screen in hex |
| `l` | | Dumps single lines (16 bytes) of sector to screen, use multiple times |

Example session:

```
C:0 H:0 S:1 > a c1 h2 s3
C:1 H:2 S:3 > r
S 00
C:1 H:2 S:3 > l
= 65 65 6E 20 63 61 75 73 65 64 20 62 79 20 74 68
C:1 H:2 S:3 > q
```

## Building

This program is written in 8088 assembly, and needs nasm to build.

The basic command for building is:

`nasm -f bin -o wread.com wread.asm`

Or by using the included makefile:

`make`

The Makefile will also attempt to build a floppy image using mtools. This
requires a base floppy image, which is not included in the distribution.

## Useful links

 - [INT 13h](https://www.stanislavs.org/helppc/int_13.html)
 - [x86 instructions](https://c9x.me/x86/)
 - [disk-xfer](https://github.com/tschak909/disk-xfer), another potentially more useful software for imaging disks
