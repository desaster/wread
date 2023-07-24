ASM=nasm

# floppy to use as a base for creating the floppy - may contain useful
# stuff like a bootable dos and debug.com
BASEFLOPPY=dos622base.img.gz

.PHONY: all wread clean always

image: wread.img

wread.img: wread
	zcat ${BASEFLOPPY} > wread.img
	[ -f autoexec.bat ] && mcopy -D o -i wread.img autoexec.bat ::autoexec.bat || true
	[ -f shut.com ] && mcopy -i wread.img shut.com ::shut.com || true
	mcopy -i wread.img wread.com ::wread.com

wread: wread.com

wread.com: always
	nasm -w+error -f bin -l wread.lst -o wread.com wread.asm

clean:
	rm -f wread.com wread.img
