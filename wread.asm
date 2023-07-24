;
; Command-line interface for reading raw sectors from a hard disk
;
; Copyright (C) 2023 Upi Tamminen
;
;   nasm -f bin -o wread.com wread.asm
;
; The CLI accepts a few single character commands:
;
;   q - quits the program
;   a c<value> h<value> s<value> - assigns cyl/head/sector values for next read
;   r - reads a raw sector into memory using the previously assigned c/h/s
;   d - dumps entire sector of 512 bytes to screen in hex
;   l - dumps single lines (16 bytes) of sector to screen, use multiple times
; 
; This program was intended to be used for imaging a hard drive of a DEC
; Rainbow 100 computer over serial connection. In it's current state it may
; however be too slow for that.
;
; Ref.
;
; INT 13h               https://www.stanislavs.org/helppc/int_13.html
; x86 instructions      https://c9x.me/x86/
;

cpu 8086
org 0x100

section .text

%define DONE 00h
%define NOT_DONE 01h

main:
.cliloop:
    mov     [clibufpos], word   0000h

    call    showvariables       ; show variables as part of the prompt
    mov     dx, cliprefix_cmd   ; prompt itself
    call    printmsg

    call    readline            ; read line from user into clibuf
    call    printnl             ; empty line
    call    handlecli           ; do stuff with clibuf

    jmp     .cliloop

    ret

;
; Exit program
;
exit:
    mov     dx, quittingmsg
    call    printmsg

    mov     ax, 4c00h
    int     21h
    hlt

;
; Read one sector (512 bytes) into buf
;
; Inputs:
;   curr_cyl
;   curr_head
;   curr_sector (1 indexed)
; Outputs:
;   ah = status  (see INT 13,STATUS)
;   al = number of sectors read
;   cf = 0 if successful
;      = 1 if error
;
readsector:
    mov     cx, [curr_sector]   ; sector number (1 indexed)

    ; track/cylinder number  (0-1023 dec., see below)
    mov     ax, [curr_cyl]      ; keep cylinder temporarily here

    mov     ch, al              ; ch = cylinder, lower 8-bits

    push    cx
    mov     cl, 6
    shl     ah, cl
    pop     cx
    or      cl, ah              ; put upper 2 bits of cylinder in cl

    mov     dh, [curr_head]     ; head number

    mov     dl, 80h             ; drive number (0=A:, 1=2nd floppy, 80h=drive 0, 81h=drive 1)
    mov     ah, 02h
    mov     al, 01h             ; number of sectors to read (1-128 dec.)

    mov     bx, buf             ; ES:BX = pointer to buffer

    ; the parameters in CX change depending on the number of cylinders;
    ; the track/cylinder number is a 10 bit value taken from the 2 high
    ; order bits of CL and the 8 bits in CH (low order 8 bits of track):
    ;
    ; |F|E|D|C|B|A|9|8|7|6|5-0|  CX
    ;  | | | | | | | | | |    `-----    sector number
    ;  | | | | | | | | `---------  high order 2 bits of track/cylinder
    ;  `------------------------  low order 8 bits of track/cyl number

    int     13h

    ; no error checking, later we'll just output the status to the user

    mov     [buflinepos], word 0000h

    ret

;
; Dump buf contents on screen
;
printbuf:
    mov     si, 0h
    mov     cl, 0h

.loop:
    or      cl, cl
    jnz     .noprefix
.prefix:
    mov     dx, cliprefix_dump  ; show a prefix character for each line
    call    printmsg
.noprefix:
    mov     al, [buf+si]
    inc     si
    inc     cl
    call    byte2hex
    cmp     cl, 10h             ; newline every 16 values
    jnz     .nonl
.nl:
    xor     cl, cl
    call    printnl
.nonl:
    cmp     si, 200h            ; dump full 512 bytes
    jnz     .loop

    ret

;
; Print a single line from buf
;
; Counter (buflinepos) is increased on every call, so this subroutine may be
; called 32 times to print the full 512 byte buffer
;
printbufl:
    mov     dx, cliprefix_dump  ; show a prefix character for each line
    call    printmsg

    mov     si, [buflinepos]    ; position in buffer
    mov     cl, 0h              ; column counter
.loop:
    mov     al, [buf+si]        ; pick one byte from buffer
    inc     si                  ; increase position
    inc     cl                  ; also increase column counter
    call    byte2hex            ; print out the byte

    cmp     si, 0200h           ; have we read full sector?
    jnge     .noreset           ; if not, just hop ahead
    mov     si, 0000h           ; if we have, reset buffer position to beginning
.noreset:
    cmp     cl, 10h             ; if we've done a full colum, this subroutine is done
    jnz     .loop

    mov     [buflinepos], si    ; store the new buffer position for next call

    call    printnl             ; newline so the prompt appears on a new line

    ret

;
; Show the c, h, s values stored by cli
;
showvariables:
    mov     dx, cylmsg
    call    printmsg
    mov     ax, [curr_cyl]
    call    word2dec
    mov     dx, word2dec_res
    call    printmsg

    mov     dx, headmsg
    call    printmsg
    mov     ax, [curr_head]
    call    word2dec
    mov     dx, word2dec_res
    call    printmsg

    mov     dx, sectormsg
    call    printmsg
    mov     ax, [curr_sector]
    call    word2dec
    mov     dx, word2dec_res
    call    printmsg

    ret

;
; Read one character into clibuf
; Outputs:
;   al = character read
;
readchar:
    push    di
.loop:
    mov     ah, 0bh     ; check input
    int     21h
    or      al, al      ; no new character?
    je      .loop       ; then keep looping

    mov     ah, 01h     ; new character, read input
    int     21h

    ; don't append newlines to clibuf
    cmp     al, 0dh
    jz      .end
    cmp     al, 0ah
    jz      .end

    ; new character is in al, let's append it to clibuf
    mov     di, [clibufpos]
    mov     [clibuf+di], al
    inc     di
    mov     [clibuf+di], byte 00h ; cli buffer is zero terminated
    mov     [clibufpos], di

.end:
    pop     di

    ; al = char
    ret

;
; read an entire line into clibuf
;
readline:
    mov     [clibuf], byte 00h
.loop:
    call    readchar ; read one character into cli buf
    cmp     al, 0dh ; was it newline?
    jz      .end
    jmp     .loop ; if not, keep going
.end:
    ret

;
; handle previously read command line
;
handlecli:
.loop:
    call    cliparser   ; call state machine
    cmp     al, DONE    ; until it signals done
    jne     .loop
    ret

;
; State machine to parse command line
; Outputs:
;   al: should the state machine stop (00h) or not (01h) ?
;
cliparser:
    jmp     [cliparser_state]

; initial state
cliparser_init:
    mov     [clibufpos], word 0000h ; reset buffer position
    mov     dl, [clibuf]            ; pick a character

    ; first thing we expect is a command
    mov     [cliparser_state], word cliparser_cmd
    mov     al, NOT_DONE
    ret

; command parsing state, checks the first character for a command
cliparser_cmd:
    or      dl, dl  ; 00h?
    jz      .done   ; on empty line don't bother with error messages

.check_q:   ; quit
    cmp     dl, 'q'
    jnz     .check_a
    jmp     exit
    ret

.check_a:   ; assign read variables (c/h/s)
    cmp     dl, 'a'
    jnz     .check_r
    mov     al, NOT_DONE
    mov     [cliparser_state], word cliparser_cc
    ret

.check_r:   ; read using previously assigned variables
    cmp     dl, 'r'
    jnz     .check_d

    call    readsector

    mov     dx, cliprefix_status
    call    printmsg

    ; we'll just show the error code without explanations
    ; https://en.wikipedia.org/wiki/INT_13H#INT_13h_AH=01h:_Get_Status_of_Last_Drive_Operation
    mov     al, ah
    call    byte2hex
    call    printnl

    mov     al, DONE
    mov     [cliparser_state], word cliparser_init
    ret

.check_d:   ; dump
    cmp     dl, 'd'
    jnz     .check_l
    call    printbuf
    mov     [cliparser_state], word cliparser_init
    mov     al, DONE
    ret

.check_l:   ; dump one line
    cmp     dl, 'l'
    jnz     .unknown
    call    printbufl
    mov     [cliparser_state], word cliparser_init
    mov     al, DONE
    ret

.unknown:   ; jump here to reset with error message
    mov     dx, unknowncmdmsg
    call    printmsg
.done:      ; or here to skip the error message
    mov     al, DONE
    mov     [cliparser_state], word cliparser_init
    ret

; control character state, used by (a)ssign to enter number parsing states
cliparser_cc:
    call    advclibuf

.check_whitespace: ; ignore whitespaces
    cmp     dl, ' '
    jnz     .check_cyl
    mov     al, NOT_DONE
    ret

.check_cyl:
    cmp     dl, 'c'
    jnz     .check_head

    mov     bx, curr_cyl
    call    setparamtarget

    mov     [cliparser_state], word cliparser_value
    mov     al, NOT_DONE
    ret

.check_head:
    cmp     dl, 'h'
    jnz     .check_sector

    mov     bx, curr_head
    call    setparamtarget

    mov     [cliparser_state], word cliparser_value
    mov     al, NOT_DONE
    ret

.check_sector:
    cmp     dl, 's'
    jnz     .unknown

    mov     bx, curr_sector
    call    setparamtarget

    mov     [cliparser_state], word cliparser_value
    mov     al, NOT_DONE
    ret

.unknown:
    mov     [cliparser_state], word cliparser_init
    mov     al, DONE
    ret

; numeric value state, read numbers and add them to paramtarget
cliparser_value:
    call    advclibuf

    or      dl, dl  ; check for zero
    jz      .is_end

.check_digit:
    cmp     dl, '0'
    jnge    .not_digit
    cmp     dl, '9'
    jnle    .not_digit
    jmp     .is_digit

.not_digit:
    mov     al, NOT_DONE
    mov     [cliparser_state], word cliparser_cc ; back to reading another cc
    ret

.is_digit:
    ; convert ascii -> number, add it to the previous value and store in paramtarget
    and     dl, 0fh         ; remove the upper bits, char becomes a number
    mov     di, [paramtarget]
    mov     ax, word [di]   ; previously accumulated number to al

    push    dx              ; mul also sets dx when doing 16-bit multiplication
    mov     bx, 000ah       ; bl = 10 for mul of base 10
    mul     bx              ; multiply ax by 10
    pop     dx              ; i think we can ignore dx and pop out our original value

    xor     dh, dh          ; set high bits to zero
    add     ax, dx          ; add new number to that
    mov     [di], ax        ; store newly accumulated number

    mov     al, NOT_DONE
    ; keep state as _value to read more numeric parts
    ret

.is_end:
    mov     [cliparser_state], word cliparser_init ; reset state machine
    mov     al, DONE ; stop
    ret

;
; Set paramtarget, which points to another variable (curr_cyl, etc).
; Additionally reset the value of that address to zero.
;
; Inputs:
;   bx: input address
;
setparamtarget:
    mov     [paramtarget], word bx
    mov     di, [paramtarget]
    mov     [di], word 0000h
    ret

;
; Advance clibuf by increasing clibufpos and reading one character from clibuf
; Outputs:
;   dl: character picked from clibuf
;
advclibuf:
    mov     si, [clibufpos]     ; take the previous clibufpos
    inc     si                  ; increase it
    mov     dl, [clibuf+si]     ; pick a character
    mov     [clibufpos], si     ; store the new increased clipbufpos
    ret

;
; Write '$' terminated string into standard output
; Inputs:
;   dx: input string
;
printmsg:
    push    ax
    mov     ah, 09h
    int     21h
    pop     ax
    ret

;
; Write a single character into standard output
; Inputs:
;   dl: character to print
;
printchar:
    push    ax
    mov     ah, 02h
    int     21h
    pop     ax
    ret

;
; Just print a newline
;
printnl:
    push    dx
    mov     dx, newline
    call    printmsg
    pop     dx
    ret

;
; Write a zero terminated buffer into standard output
; Inputs:
;   dx: input buffer
;
; printmsg0:
;     push ax
;     push cx
;     push si
;
;     mov si, dx      ; first place the address in si
; .loop:
;     mov dl, [si]    ; take a character from buffer into dl
;     or dl, dl       ; zero?
;     jz .end         ; then go to end
;     mov ah, 02h     ; otherwise print char
;     int 21h
;     inc si          ; increase index for next round
;     jmp .loop       ; and loop again
;
; .end:
;     pop si
;     pop cx
;     pop ax
;     ret

;
; Convert byte to hex and display it on screen
; Inputs:
;   al: value to convert
;
byte2hex:
    push    si
    push    ax
    push    bx
    push    cx
    push    dx

    ; al = value to work with

    mov     bl, al          ; nibble2hex input should be in bl
    mov     cl, 4
    ror     bl, cl          ; shift right so we can display the upper nibble
    call    nibble2hex

    mov     bl, al          ; nibble2hex input should be in bl 
    call    nibble2hex

    mov     dl, ' '         ; show whitespace to visually separate subsequent hex values
    mov     ah, 02h
    int     21h

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     si

    ret

;
; Convert nibble (4-bits) to hex and display it on screen
; Inputs:
;   bl: nibble
;
nibble2hex:
    push    ax
    and     bl, 0fh         ; remove the upper bits
    cmp     bl, 10          ; compare to 10
    jae     .letter         ; higher or equal to 10? go to .letter
.number:
    add     bl, 48          ; it's less than 10, add 48 and we should have a 0-9

    mov     dl, bl          ; print it out
    mov     ah, 02h
    int     21h

    jmp     .done
.letter:
    sub     bl, 10          ; it's more than 10, subtract 10
    add     bl, 65          ; and add 65 so we should have A-F

    mov     dl, bl          ; print it out
    mov     ah, 02h
    int     21h

.done:
    pop     ax
    ret

;
; Convert 16-bit binary value to ascii decimal representation
; (ChatGPT generated with some fixes)
;
; Inputs:
;   ax: 16-bit source value
; Outputs:
;   word2dec_res
;
word2dec:
    mov     bx, 0ah     ; Divisor (decimal 10)
    mov     cx, 00h     ; Initialize the counter for the decimal digits

.convert_to_decimal:
    xor     dx, dx      ; Clear DX before the division
    div     bx          ; Divide AX (AH:AL) by BX. Quotient in AL, Remainder in AH
    push    dx          ; Push the remainder onto the stack
    inc     cx          ; Increment the counter

    ; Check if quotient is not zero (end of division)
    or      ax, ax
    jnz     .convert_to_decimal

    ; At this point, the remainder stack contains the decimal digits in reverse order,
    ; and CX holds the number of digits.
    mov     di, word2dec_res    ; DI points to the buffer where ASCII characters will be stored
    add     di, cx              ; Move DI to the end of the buffer
    mov     byte [di], '$'
    mov     di, word2dec_res    ; And again to the beginning of the buffer
    
.convert_to_ascii:
    pop     dx                  ; Pop a decimal digit from the stack
    add     dl, '0'             ; Convert the digit to its ASCII representation
    mov     [di], dl            ; Store the ASCII character
    inc     di                  ; Increment DI for the next iteration

    loop    .convert_to_ascii   ; Repeat until all digits are processed

    ret

section .data
    ; not used, user should know these when reading
    ;total_cyls db 20
    ;total_heads db 16
    ;total_sectors db 63

    curr_cyl dw 0x0000
    curr_head dw 0x0000
    curr_sector dw 0x0001 ; 1 indexed

    ; pointer to whichever value we are currently writing to
    paramtarget dw curr_cyl

    cliparser_state dw cliparser_init

    cliprefix_cmd db ' > $'
    cliprefix_dump db '= $'
    cliprefix_status db 'S $'

    word2dec_res db 10 dup('Z'), '$' ; Buffer to store ASCII representation of the number

    newline db 0x0d, 0x0a, '$'
    unknowncmdmsg db 'Unknown command', 0dh, 0ah, '$'
    quittingmsg db 0dh, 0ah, 'Quit', 0dh, 0ah, '$'
    wheemsg db 'Wheee!', 0dh, 0ah, '$'

    cylmsg db 'C:', '$'
    headmsg db ' H:', '$'
    sectormsg db ' S:', '$'

section .bss
    buf resb 512
    clibuf resb 64
    clibufpos resw 1
    buflinepos resw 1 ; position when reading line by line

; vim: set ft=nasm:
