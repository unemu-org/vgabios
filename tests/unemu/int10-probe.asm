; SPDX-License-Identifier: LGPL-2.1-or-later
; INT 10h probe for the unemu fork of the LGPL VGABIOS.
; Copyright (C) 2026 the contributors to the unemu fork of the LGPL VGABIOS.
;
; A boot program for a 1.2M floppy. It loads its other sectors, runs checks
; of the video BIOS in modes 03h, 0Dh and 13h, logs the results, returns to
; mode 03h, prints the log by teletype and halts with interrupts disabled.
; The checks read registers and video memory back; they do not judge the
; picture. Each check logs "name ok" or "name FAIL"; the last line gives the
; number of failures. 80286 real-mode code only (nasm "cpu 286").
; Build: see flake.nix (packages.int10-probe).
cpu 286
bits 16
org 0x7C00

LOG     equ 0x5000          ; log buffer (segment 0)
SAVEBUF equ 0x1000          ; segment of the AH=1Ch state buffer
NSECT   equ 8               ; sectors loaded after the boot sector

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld
    mov [bootdrv], dl
    mov si, 3                   ; tries
.rd:
    mov ax, 0x0200 + NSECT
    mov bx, 0x7E00
    mov cx, 0x0002
    xor dh, dh
    mov dl, [bootdrv]
    int 0x13
    jc .rt
    jmp main
.rt:
    xor ah, ah                  ; reset the drive and try again
    mov dl, [bootdrv]
    int 0x13
    dec si
    jnz .rd
load_fail:
    mov si, msg_load
.l: lodsb
    or al, al
    jz .h
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .l
.h: cli
    hlt
    jmp .h
msg_load db "LOAD FAIL", 0
bootdrv  db 0
    times 510-($-$$) db 0
    dw 0xAA55

; ---------------------------------------------------------------- helpers
logp dw LOG

; log the zero-terminated string at DS:SI
log_str:
    push ax
    push di
    mov di, [logp]
.l: lodsb
    or al, al
    jz .e
    mov [di], al
    inc di
    jmp .l
.e: mov [logp], di
    pop di
    pop ax
    ret

; log AX as 4 hex digits
log_hex:
    push ax
    push cx
    push dx
    push di
    mov di, [logp]
    mov dx, ax
    mov cx, 4
.l: rol dx, 4
    mov al, dl
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .s
    add al, 7
.s: mov [di], al
    inc di
    loop .l
    mov [logp], di
    pop di
    pop dx
    pop cx
    pop ax
    ret

%macro LOGS 1
    jmp %%skip
%%str db %1, 0
%%skip:
    push si
    mov si, %%str
    call log_str
    pop si
%endmacro

; check: CF clear = pass. Logs " name ok" or " name FAIL".
%macro CHECK 1
    jc %%fail
    LOGS {" ", %1, " ok"}
    jmp %%done
%%fail:
    LOGS {" ", %1, " FAIL"}
    inc word [fails]
%%done:
%endmacro

fails dw 0
tmp1  dw 0
tmp2  dw 0

; AX == BX -> CF clear
eq:
    cmp ax, bx
    je .y
    stc
    ret
.y: clc
    ret

; read CRTC register AL (colour base) into AL
crtc_read:
    push dx
    mov dx, 0x3D4
    cli
    out dx, al
    inc dx
    in al, dx
    sti
    pop dx
    ret

; read attribute controller register AL into AL, keep PAS set
attr_read:
    push dx
    push bx
    mov bl, al
    cli
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, bl
    or al, 0x20
    out dx, al
    inc dx
    in al, dx
    mov bl, al
    mov dx, 0x3DA
    in al, dx
    sti
    mov al, bl
    pop bx
    pop dx
    ret

; ---------------------------------------------------------------- main
main:
    ; ---- state after POST
    LOGS {"vgabios INT 10h probe", 13}
    LOGS "POST"
    mov ah, 0x0F
    int 0x10
    push ax
    LOGS " 0F:"
    pop ax
    push ax
    call log_hex                ; AH cols, AL mode
    pop ax
    mov bx, 0x5003
    call eq
    CHECK "mode3"
    mov ax, 0x1A00
    xor bx, bx
    int 0x10
    mov [tmp1], ax
    mov [tmp2], bx
    LOGS " 1A:"
    mov ax, [tmp1]
    call log_hex
    mov ax, [tmp2]
    call log_hex
    mov al, [tmp1]              ; AL=1Ah: function supported
    xor ah, ah
    mov bx, 0x001A
    call eq
    jc .dcc
    mov ax, [tmp2]              ; BL=08h colour VGA, BH=00h no alternate
    mov bx, 0x0008
    call eq
.dcc:
    CHECK "dcc"
    mov ah, 0x12
    mov bx, 0xFF10
    int 0x10
    mov [tmp2], bx
    LOGS " 12/10:"
    mov ax, [tmp2]
    call log_hex
    mov ax, [tmp2]              ; BH=00h colour, BL=03h 256K
    mov bx, 0x0003
    call eq
    CHECK "egainfo"
    LOGS 13

    ; ---- mode 03h: mode set, BDA, font in plane 2
    LOGS "M03"
    mov ax, 0x0013              ; other BDA values, plane 2 cleared
    int 0x10
    mov ax, 0x0003
    int 0x10
    mov al, [0x449]
    xor ah, ah
    mov bx, 3
    call eq
    CHECK "bda.mode"
    mov ax, [0x44A]
    mov bx, 80
    call eq
    CHECK "bda.cols"
    mov al, [0x484]
    xor ah, ah
    mov bx, 24
    call eq
    CHECK "bda.rows"
    mov ax, [0x485]
    mov bx, 16
    call eq
    CHECK "bda.char"
    LOGS 13
    call font_check
    CHECK "font.plane2"
    LOGS 13
    ; cursor shape and position
    mov ah, 0x01
    mov cx, 0x0607
    int 0x10
    mov ah, 0x02
    xor bh, bh
    mov dx, 0x0A14              ; row 10, col 20
    int 0x10
    mov ah, 0x03
    xor bh, bh
    mov cx, 0xFFFF
    mov dx, 0xFFFF
    int 0x10
    push dx
    mov ax, cx
    mov bx, 0x0607
    call eq
    CHECK "curshape"
    pop ax
    mov bx, 0x0A14
    call eq
    CHECK "curpos"
    ; teletype moves the cursor and writes char+attr
    mov ax, 0x0E41
    xor bx, bx
    int 0x10
    mov ah, 0x03
    xor bh, bh
    mov dx, 0xFFFF
    int 0x10
    mov ax, dx
    mov bx, 0x0A15
    call eq
    CHECK "tty.cur"
    push es
    mov ax, 0xB800
    mov es, ax
    mov ax, [es:(10*80+20)*2]
    pop es
    mov bx, 0x0741
    call eq
    CHECK "tty.cell"
    ; read char/attr at cursor - 1
    mov ah, 0x02
    xor bh, bh
    mov dx, 0x0A14
    int 0x10
    mov ah, 0x08
    xor bh, bh
    int 0x10
    mov bx, 0x0741
    call eq
    CHECK "rdchar"
    ; scroll window up one line: row 10 col 20 cell moves to row 9
    mov ax, 0x0601
    mov bh, 0x07
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    push es
    mov ax, 0xB800
    mov es, ax
    mov ax, [es:(9*80+20)*2]
    pop es
    mov bx, 0x0741
    call eq
    CHECK "scroll"
    LOGS 13
    ; active page 1
    mov ax, 0x0501
    int 0x10
    mov al, 0x0C
    call crtc_read
    mov ah, al
    mov al, 0x0D
    call crtc_read
    push ax
    LOGS " p1crtc:"
    pop ax
    push ax
    call log_hex
    LOGS " p1bda:"
    mov ax, [0x44E]
    call log_hex
    pop ax
    mov bx, 0x0800              ; 4096-byte page, word address
    call eq
    CHECK "page1"
    mov ax, 0x0500
    int 0x10
    LOGS 13
    ; AH=1Ch save/restore state round trip (vectors 1Fh, 43h)
    call state_check
    LOGS 13

    ; ---- mode 0Dh: pixel write/read, planes, pel panning, page
    LOGS "M0D"
    mov ax, 0x000D
    int 0x10
    mov ah, 0x0F
    int 0x10
    mov bx, 0x280D
    and ax, 0xFF7F
    call eq
    CHECK "mode"
    mov ax, 0x0C09              ; colour 9 at x=5 y=3
    xor bh, bh
    mov cx, 5
    mov dx, 3
    int 0x10
    mov ax, 0x0DFF
    xor bh, bh
    mov cx, 5
    mov dx, 3
    int 0x10
    xor ah, ah
    mov bx, 9
    call eq
    CHECK "pixel"
    ; read the four planes at byte 3*40, bit 0x04
    xor bx, bx                  ; BL = plane bits
    xor cx, cx                  ; CL = plane
    cli
    mov dx, 0x3CE
    mov ax, 0x0005              ; read mode 0
    out dx, ax
.pl:
    mov dx, 0x3CE
    mov al, 4
    out dx, al
    inc dx
    mov al, cl
    out dx, al
    push es
    mov ax, 0xA000
    mov es, ax
    mov al, [es:3*40]
    pop es
    test al, 0x04
    jz .pn
    mov al, 1
    shl al, cl
    or bl, al
.pn:
    inc cl
    cmp cl, 4
    jb .pl
    sti
    push bx
    LOGS " planes:"
    pop ax
    push ax
    call log_hex
    pop ax
    mov bx, 0x0009
    call eq
    CHECK "planes"
    ; pel panning through AX=1000h, read back with 1007h and the port
    mov ax, 0x1000
    mov bx, 0x0413
    int 0x10
    mov ax, 0x1007
    mov bx, 0x0013
    int 0x10
    mov al, bh
    xor ah, ah
    mov bx, 4
    call eq
    CHECK "pan.bios"
    mov al, 0x13
    call attr_read
    xor ah, ah
    mov bx, 4
    call eq
    CHECK "pan.port"
    LOGS 13
    ; active page 1: CRTC start in bytes
    mov ax, 0x0501
    int 0x10
    mov al, 0x0C
    call crtc_read
    mov ah, al
    mov al, 0x0D
    call crtc_read
    push ax
    LOGS " p1crtc:"
    pop ax
    push ax
    call log_hex
    pop ax
    mov bx, 0x2000
    call eq
    CHECK "page1"
    LOGS 13

    ; ---- mode 13h
    LOGS "M13"
    mov ax, 0x0013
    int 0x10
    mov ax, 0x0C55
    xor bh, bh
    mov cx, 10
    mov dx, 10
    int 0x10
    push es
    mov ax, 0xA000
    mov es, ax
    mov al, [es:10*320+10]
    pop es
    xor ah, ah
    mov bx, 0x55
    call eq
    CHECK "pixel.mem"
    mov ax, 0x0DFF
    xor bh, bh
    mov cx, 10
    mov dx, 10
    int 0x10
    xor ah, ah
    mov bx, 0x55
    call eq
    CHECK "pixel.bios"
    LOGS 13
    ; DAC set/get single register
    mov ax, 0x1010
    mov bx, 0x0005
    mov dh, 0x11
    mov ch, 0x22
    mov cl, 0x33
    int 0x10
    xor cx, cx
    xor dx, dx
    mov ax, 0x1015
    mov bx, 0x0005
    int 0x10
    mov al, dh
    mov ah, ch
    mov bx, 0x2211
    call eq
    CHECK "dac.rg"
    xor ah, ah
    mov al, cl
    mov bx, 0x33
    call eq
    CHECK "dac.b"
    ; the same through the ports
    cli
    mov dx, 0x3C7
    mov al, 5
    out dx, al
    mov dx, 0x3C9
    in al, dx
    mov ah, al                  ; red
    in al, dx                   ; green
    mov cl, al
    in al, dx                   ; blue
    sti
    mov ch, al
    mov al, cl
    mov bx, 0x1122
    call eq
    jc .dp
    mov al, ch
    xor ah, ah
    mov bx, 0x33
    call eq
.dp:
    CHECK "dac.port"
    LOGS 13

    ; ---- back to text, print the log
    mov ax, 0x0003
    int 0x10
    LOGS "fails:"
    mov ax, [fails]
    call log_hex
    mov di, [logp]
    mov byte [di], 0
    mov si, LOG
.p: lodsb
    or al, al
    jz .done
    cmp al, 13
    jne .c
    mov ax, 0x0E0D
    xor bx, bx
    int 0x10
    mov al, 10
.c: mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .p
.done:
    cli
    hlt
    jmp .done

; ---------------------------------------------------------------- checks
; Compare the 8x16 font in plane 2 with the ROM font from AX=1130h BH=06h.
font_check:
    push es
    xor bp, bp
    mov ax, 0x1130
    mov bh, 0x06
    int 0x10                    ; ES:BP = ROM 8x16 font
    mov [fontseg], es
    mov [fontoff], bp
    pop es
    mov bx, 0xFFFF              ; no font pointer: FAIL
    mov ax, [fontseg]
    or ax, [fontoff]
    jz .log
    push es
    push ds
    cli
    ; plane 2 access, as vgabios get_font_access
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0402
    out dx, ax
    mov ax, 0x0704
    out dx, ax
    mov ax, 0x0300
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0204
    out dx, ax
    mov ax, 0x0005
    out dx, ax
    mov ax, 0x0406
    out dx, ax
    mov ax, 0xA000
    mov es, ax
    mov si, [fontoff]
    mov ds, [fontseg]
    xor di, di
    xor bx, bx                  ; mismatching bytes
    mov cx, 256
.ch:
    push cx
    mov cx, 16
.by:
    lodsb
    cmp al, [es:di]
    je .ok
    inc bx
.ok:
    inc di
    loop .by
    add di, 16
    pop cx
    loop .ch
    pop ds
    ; release, as vgabios release_font_access (colour)
    mov dx, 0x3C4
    mov ax, 0x0100
    out dx, ax
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0304
    out dx, ax
    mov ax, 0x0300
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0E06
    out dx, ax
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    sti
    pop es
.log:
    push bx
    LOGS " fontdiff:"
    pop ax
    push ax
    call log_hex
    pop ax
    or ax, ax
    jz .y
    stc
    ret
.y: clc
    ret
fontseg dw 0
fontoff dw 0

; AH=1Ch with CX=7 (hardware, BIOS data and DAC state): size, save, change
; one item of each part and the INT 1Fh/43h vectors, restore, compare.
state_check:
    mov ax, [0x7C]              ; keep the real vectors
    mov [ovec], ax
    mov ax, [0x7E]
    mov [ovec+2], ax
    mov ax, [0x10C]
    mov [ovec+4], ax
    mov ax, [0x10E]
    mov [ovec+6], ax
    mov word [0x7C], 0x5678
    mov word [0x7E], 0x1234
    mov word [0x10C], 0xDEF0
    mov word [0x10E], 0x9ABC
    mov ax, 0x1015              ; DAC register 7 before the save
    mov bx, 0x0007
    int 0x10
    mov [dac7], dh
    mov [dac7+1], ch
    mov [dac7+2], cl
    mov al, 0x0A                ; CRTC cursor start before the save
    call crtc_read
    mov [crtc0a], al
    mov ax, 0x1C00
    mov cx, 0x0007
    int 0x10
    mov [tmp1], ax
    mov [tmp2], bx
    LOGS " 1C00:"
    mov ax, [tmp1]
    call log_hex
    LOGS "/"
    mov ax, [tmp2]
    call log_hex
    push es
    mov ax, SAVEBUF
    mov es, ax
    xor bx, bx
    mov ax, 0x1C01
    mov cx, 0x0007
    int 0x10
    pop es
    xor ah, ah
    mov bx, 0x001C
    call eq
    CHECK "1C.save"
    ; change each part
    mov word [0x7C], 0
    mov word [0x7E], 0
    mov word [0x10C], 0
    mov word [0x10E], 0
    mov byte [0x449], 0x13
    mov ax, 0x1010
    mov bx, 0x0007
    mov dh, 0x3F
    mov cx, 0x3F3F
    int 0x10
    cli
    mov dx, 0x3D4
    mov ax, 0x200A              ; cursor off
    out dx, ax
    sti
    push es
    mov ax, SAVEBUF
    mov es, ax
    xor bx, bx
    mov ax, 0x1C02
    mov cx, 0x0007
    int 0x10
    pop es
    xor ah, ah
    mov bx, 0x001C
    call eq
    CHECK "1C.rest"
    mov ax, [0x7C]
    mov bx, 0x5678
    call eq
    jc .f
    mov ax, [0x7E]
    mov bx, 0x1234
    call eq
    jc .f
    mov ax, [0x10C]
    mov bx, 0xDEF0
    call eq
    jc .f
    mov ax, [0x10E]
    mov bx, 0x9ABC
    call eq
.f:
    CHECK "1C.vectors"
    LOGS 13
    mov al, [0x449]
    xor ah, ah
    mov bx, 3
    call eq
    CHECK "1C.bda"
    mov ax, 0x1015
    mov bx, 0x0007
    xor cx, cx
    xor dx, dx
    int 0x10
    mov al, dh
    mov ah, ch
    mov bx, [dac7]
    call eq
    jc .d
    mov al, cl
    xor ah, ah
    mov bl, [dac7+2]
    xor bh, bh
    call eq
.d:
    CHECK "1C.dac"
    mov al, 0x0A
    call crtc_read
    xor ah, ah
    mov bl, [crtc0a]
    xor bh, bh
    call eq
    CHECK "1C.hw"
    mov ax, [ovec]              ; put the real vectors back
    mov [0x7C], ax
    mov ax, [ovec+2]
    mov [0x7E], ax
    mov ax, [ovec+4]
    mov [0x10C], ax
    mov ax, [ovec+6]
    mov [0x10E], ax
    ret
ovec   dw 0, 0, 0, 0
dac7   db 0, 0, 0
crtc0a db 0

    times (NSECT+1)*512-($-$$) db 0
