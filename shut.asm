; 
; nasm -f bin -o shut.com shut.asm
;
; Shuts down computer
;
; For rapid development, add this to your autoexec.bat when running with qemu
;
cpu 8086
org 0x100

section .text
    # http://www.delorie.com/djgpp/doc/rbinter/id/08/14.html
    mov ax, 5307h
    mov bx, 1
    mov cx, 3
    int 15h
main:
