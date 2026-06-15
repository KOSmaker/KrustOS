[org 0x7C00]
[bits 16]

IMG_SIG_SECTOR equ 57
IMG_PART_SECTORS equ 0x007FFFFF

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    mov [boot_drive], dl
    mov [0x7A00], dl

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, IMG_SIG_SECTOR
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x0600
    int 0x13
    jc sig_error

    mov si, img_sig
    mov di, 0x0600
.sig_loop:
    mov al, [si]
    test al, al
    jz load_kernel
    cmp al, [di]
    jne sig_error
    inc si
    inc di
    jmp .sig_loop

load_kernel:
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x7E00
    int 0x13
    jc disk_error

    jmp 0x0000:0x7E00

sig_error:
    mov si, sig_msg
    jmp print_msg

disk_error:
    mov si, err_msg

print_msg:
.loop:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .loop
.halt:
    cli
.hang:
    hlt
    jmp .hang

boot_drive db 0
img_sig db 'KRUSTIMG1', 0
sig_msg db 'Invalid base.img signature!', 0
err_msg db 'Disk read error!', 0

times 446-($-$$) db 0

db 0x80, 0x00, 0x02, 0x00
db 0x0C, 0xFE, 0xFF, 0xFF
dd 0x00000001
dd IMG_PART_SECTORS

times 16 * 3 db 0
dw 0xAA55
