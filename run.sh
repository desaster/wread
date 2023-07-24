#!/bin/sh

# when using -nographic, qemu can be exited with C-A X
# https://superuser.com/a/1211516

qemu-system-i386 \
    -fda wread.img \
    -hda wread-hdd-10mb.img \
    -boot order=a \
    -nographic \
    $*
