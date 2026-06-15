[org 0x7E00]
[bits 16]

ATTR_WHITE equ 0x0F
ATTR_CYAN  equ 0x0B
ATTR_GREEN equ 0x0A
ATTR_RED   equ 0x0C

NAME_SECTOR      equ 50
ERR_SECTOR       equ 51
FS_HDR_SECTOR    equ 52
FS_TABLE_SECTOR  equ 53
FS_TABLE_SECTORS equ 4

TERM_NAME_ADDR equ 0xD000
TERM_ERR_ADDR  equ 0xD100
TERM_DIR_ADDR  equ 0xD200
TERM_RESP_ADDR equ 0xD300
TERM_RESP_SIZE equ 1536
TERM_DIR_SIZE  equ 96
FS_HDR_ADDR    equ 0xD900
FS_TABLE_ADDR  equ 0xDB00

FS_ENTRY_SIZE  equ 32
FS_MAX_ENTRIES equ 64
FS_FLAG_USED   equ 0x01
FS_FLAG_DIR    equ 0x02

KAPI_FN_EXEC equ 0x00
KAPI_FN_INIT equ 0x01

TERM_RESP_NONE  equ 0
TERM_RESP_INFO  equ 1
TERM_RESP_ERROR equ 2
TERM_RESP_ERRORLIST equ 3

TERM_ACT_NONE    equ 0
TERM_ACT_CLEAR   equ 1
TERM_ACT_BACKCMD equ 2
TERM_ACT_HALT    equ 3

CMD_FLAG_PREFIX equ 0x01
CMD_FLAG_HIDDEN equ 0x02
CMD_FLAG_WORD   equ 0x04
CMD_FLAG_FS     equ 0x08

BOOT_DRIVE equ boot_drive_val

start:
    cli
    ; Keep boot drive both from DL and from the shared low-memory slot.
    mov  [boot_drive_val], dl
    mov  [0x7A00], dl
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    call install_kernel_api
    sti
    call term_init_state
    call launch_visual_os

    call cls
    mov  byte [v_row], 0
    mov  byte [v_col], 0
    mov  word [v_len], 0

    mov  byte [v_attr], ATTR_CYAN
    mov  si, s_banner
    call puts

    call do_prompt
    jmp  main_loop

launch_visual_os:
    call load_visualos
    jc   .fallback
    jmp  0x2000:0x0000
.fallback:
    ret

install_kernel_api:
    push ax
    mov  word [0x0180], kernel_api_entry
    mov  word [0x0182], 0x0000
    pop  ax
    ret

kernel_api_entry:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov  ax, ds
    mov  es, ax
    xor  ax, ax
    mov  ds, ax
    sti

    cmp  ah, KAPI_FN_INIT
    je   .init
    cmp  ah, KAPI_FN_EXEC
    je   .exec
    xor  ax, ax
    jmp  .done

.init:
    xor  ax, ax
    mov  es, ax
    call term_init_state
    xor  ax, ax
    jmp  .done

.exec:
    call term_exec_api

.done:
    pop  es
    pop  ds
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    iret

; =======================
; MAIN LOOP (со стрелками)
; =======================
main_loop:
    call kbd_read

    test al, al
    jnz  .check_normal

    ; спецклавиши
    cmp  ah, 0x4B
    je   .arrow_left
    cmp  ah, 0x4D
    je   .arrow_right
    cmp  ah, 0x47
    je   .arrow_home
    cmp  ah, 0x4F
    je   .arrow_end
    jmp  main_loop

.arrow_left:
    cmp  word [v_cur], 0
    je   main_loop
    dec  word [v_cur]
    dec  byte [v_col]
    call move_cur
    jmp  main_loop

.arrow_right:
    mov  bx, [v_cur]
    cmp  bx, [v_len]
    jae  main_loop
    inc  word [v_cur]
    inc  byte [v_col]
    call move_cur
    jmp  main_loop

.arrow_home:
    mov  ax, [v_cur]
    sub  byte [v_col], al
    mov  word [v_cur], 0
    call move_cur
    jmp  main_loop

.arrow_end:
    mov  ax, [v_len]
    sub  ax, [v_cur]
    add  byte [v_col], al
    mov  ax, [v_len]
    mov  [v_cur], ax
    call move_cur
    jmp  main_loop

.check_normal:
    cmp  al, 13
    je   .enter
    cmp  al, 8
    je   .bs
    cmp  al, 32
    jb   main_loop

    mov  bx, [v_len]
    cmp  bx, 62
    jae  main_loop

    ; сдвигаем символы вправо от v_cur
    mov  cx, [v_len]
    sub  cx, [v_cur]
    jz   .insert_end
    mov  si, v_buf
    add  si, [v_len]
    mov  di, si
    inc  di
.shift_right:
    dec  si
    dec  di
    mov  bl, [si]
    mov  [di], bl
    loop .shift_right

.insert_end:
    mov  bx, [v_cur]
    mov  [v_buf + bx], al
    inc  word [v_len]
    inc  word [v_cur]

    push ax
    mov  si, v_buf
    add  si, bx
    mov  cx, [v_len]
    sub  cx, bx
.redraw_right:
    lodsb
    mov  ah, ATTR_WHITE
    call putc_raw
    inc  byte [v_col]
    loop .redraw_right
    pop  ax

    mov  bx, [v_len]
    sub  bx, [v_cur]
    sub  byte [v_col], bl
    call move_cur
    jmp  main_loop

.enter:
    mov  bx, [v_len]
    sub  bx, [v_cur]
    add  byte [v_col], bl
    call move_cur
    call newline
    mov  word [v_cur], 0
    call exec_cmd
    jmp  main_loop

.bs:
    cmp  word [v_cur], 0
    je   main_loop
    dec  word [v_cur]
    dec  word [v_len]
    dec  byte [v_col]

    mov  si, v_buf
    add  si, [v_cur]
    mov  di, si
    inc  si
    mov  cx, [v_len]
    sub  cx, [v_cur]
    jz   .bs_done
    rep  movsb

.bs_done:
    push ax
    mov  si, v_buf
    add  si, [v_cur]
    mov  cx, [v_len]
    sub  cx, [v_cur]
    call move_cur
.bs_redraw:
    test cx, cx
    jz   .bs_clear
    lodsb
    mov  ah, ATTR_WHITE
    call putc_raw
    inc  byte [v_col]
    dec  cx
    jmp  .bs_redraw
.bs_clear:
    mov  al, ' '
    mov  ah, ATTR_WHITE
    call putc_raw
    pop  ax

    mov  bx, [v_len]
    sub  bx, [v_cur]
    sub  byte [v_col], bl
    call move_cur
    jmp  main_loop

; =======================
; COMMAND HANDLER
; =======================
exec_cmd:
    mov  bx, [v_len]
    mov  byte [v_buf + bx], 0
    mov  word [v_len], 0

    cmp  bx, 0
    je   cmd_done

    mov  si, v_buf
    mov  di, v_tmp
.upper_loop:
    lodsb
    test al, al
    jz   .upper_done
    cmp  al, 'a'
    jb   .upper_store
    cmp  al, 'z'
    ja   .upper_store
    sub  al, 32
.upper_store:
    stosb
    jmp  .upper_loop
.upper_done:
    xor  al, al
    stosb

    mov  si, v_tmp
    mov  di, c_switchos
    call cmp_str
    je   cmd_switchos

    mov  si, v_tmp
    mov  di, c_disk
    call cmp_str
    je   cmd_disk

    mov  si, v_tmp
    mov  di, c_hello
    call cmp_str
    je   cmd_hello

    mov  si, v_tmp
    mov  di, c_help
    call cmp_str
    je   cmd_help

    mov  si, v_tmp
    mov  di, c_clear
    call cmp_str
    je   cmd_clear

    mov  si, v_tmp
    mov  di, c_restart
    call cmp_str
    je   cmd_restart

    mov  si, v_tmp
    mov  di, c_reboot
    call cmp_str
    je   cmd_restart

    mov  si, v_tmp
    mov  di, c_shutdown
    call cmp_str
    je   cmd_shutdown

    mov  byte [v_attr], ATTR_RED
    mov  si, s_err1
    call puts
    mov  si, v_buf
    call puts
    mov  si, s_err2
    call puts
    call newline
    jmp  cmd_done

cmd_hello:
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_sys
    call puts
    mov  si, s_hello
    call puts
    call newline
    jmp  cmd_done

cmd_help:
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_sys
    call puts
    mov  si, s_help
    call puts
    jmp  cmd_done

cmd_clear:
    call cls
    mov  byte [v_row], 0
    mov  byte [v_col], 0
    jmp  cmd_done

cmd_restart:
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_sys
    call puts
    mov  si, s_restart
    call puts
    call newline
    call reboot_system

cmd_shutdown:
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_sys
    call puts
    mov  si, s_shutdown
    call puts
    call newline
    call poweroff_system

cmd_disk:
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_sys
    call puts
    mov  si, s_disktest
    call puts
    call newline
    call disk_test
    jmp  cmd_done

cmd_switchos:
    call loading_screen
    call load_visualos
    jc   cmd_done
    jmp  0x2000:0x0000

; =======================
; LOADING SCREEN
; =======================
loading_screen:
    ; очищаем экран
    call cls
    mov  byte [v_row], 0
    mov  byte [v_col], 0

    ; печатаем 10 пустых строк (центрируем по вертикали)
    mov  cx, 10
.blank_lines:
    call newline
    loop .blank_lines

    ; печатаем "  Switching to TerminalOS..." по центру (col=26)
    mov  byte [v_col], 22
    mov  byte [v_attr], ATTR_CYAN
    mov  si, s_loading1
    call puts

    call newline
    call newline

    ; печатаем "  [ Loading... ]" по центру
    mov  byte [v_col], 30
    mov  byte [v_attr], ATTR_WHITE
    mov  si, s_loading2
    call puts

    ; анимация точек — пишем 3 раза ". " с задержкой
    mov  cx, 3
.dot_loop:
    push cx
    ; задержка ~0.5 сек через пустой цикл
    mov  cx, 0xFFFF
.delay:
    nop
    nop
    loop .delay

    pop  cx
    loop .dot_loop

    ; финальное сообщение
    call newline
    call newline
    mov  byte [v_col], 27
    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_loading3
    call puts

    ; ещё пауза
    mov  cx, 0xFFFF
.final_delay:
    nop
    nop
    loop .final_delay

    ret

load_visualos:
    ; Загружаем KrustOSvisual через LBA в отдельный сегмент памяти.
    mov  si, term_load_dap
    mov  ah, 0x42
    mov  dl, [boot_drive_val]
    int  0x13
    jc   .load_err
    clc
    ret
.load_err:
    mov  byte [v_attr], ATTR_RED
    mov  si, s_load_err
    call puts
    call newline
    stc
    ret

cmd_done:
    call do_prompt
    ret

; =======================
; TERMINALOS KERNEL API
; =======================
term_init_state:
    call term_reset_response
    mov  byte [term_current_dir], 0

    mov  di, TERM_NAME_ADDR
    mov  cx, 16
    call term_zero_block

    mov  di, TERM_ERR_ADDR
    mov  cx, 8*32
    call term_zero_block

    mov  di, TERM_DIR_ADDR
    mov  cx, TERM_DIR_SIZE
    call term_zero_block

    call term_load_name
    call term_load_errors
    call fs_load
    call fs_ensure_ready
    call fs_ensure_visual_layout
    call fs_refresh_path
    ret

term_exec_api:
    call term_reset_response
    call term_copy_command

    cmp  byte [term_raw_buf], 0
    je   .done

    mov  bx, term_cmd_table
.find:
    mov  di, [bx]
    test di, di
    jz   .unknown
    mov  dl, [bx+6]
    mov  si, term_upper_buf
    call term_match_entry
    je   .run
    add  bx, 7
    jmp  .find

.run:
    call word [bx+4]
    jmp  .done

.unknown:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_unknown1
    call term_append_string
    mov  si, term_raw_buf
    call term_append_string
    mov  si, s_term_unknown2
    call term_append_string
    mov  si, term_raw_buf
    call term_log_error

.done:
    mov  al, [term_resp_kind]
    mov  ah, [term_resp_action]
    ret

term_copy_command:
    push ax
    push bx
    push cx
    push di

    mov  di, term_raw_buf
    mov  bx, term_upper_buf
    mov  cx, 63

.loop:
    mov  al, [es:si]
    inc  si
    mov  [di], al
    inc  di

    mov  dl, al
    cmp  dl, 'a'
    jb   .store_upper
    cmp  dl, 'z'
    ja   .store_upper
    sub  dl, 32

.store_upper:
    mov  [bx], dl
    inc  bx

    test al, al
    jz   .done
    loop .loop

    mov  byte [di], 0
    mov  byte [bx], 0

.done:
    pop  di
    pop  cx
    pop  bx
    pop  ax
    ret

term_match_entry:
    push si
    push di
    push ax

.loop:
    mov  al, [di]
    test al, al
    jz   .pattern_done
    cmp  al, [si]
    jne  .neq
    inc  si
    inc  di
    jmp  .loop

.pattern_done:
    test dl, CMD_FLAG_PREFIX
    jnz  .prefix_ok
    cmp  byte [si], 0
    jne  .neq
    jmp  .eq

.prefix_ok:
    test dl, CMD_FLAG_WORD
    jz   .eq
    mov  al, [si]
    test al, al
    jz   .eq
    cmp  al, ' '
    je   .eq

.neq:
    pop  ax
    pop  di
    pop  si
    mov  ax, 1
    or   ax, ax
    ret

.eq:
    pop  ax
    pop  di
    pop  si
    xor  ax, ax
    ret

term_reset_response:
    push ax
    push cx
    push di
    push es

    mov  byte [term_resp_kind], TERM_RESP_NONE
    mov  byte [term_resp_action], TERM_ACT_NONE
    mov  word [term_resp_ptr], TERM_RESP_ADDR

    xor  ax, ax
    mov  es, ax
    mov  di, TERM_RESP_ADDR
    mov  cx, TERM_RESP_SIZE
    rep  stosb

    pop  es
    pop  di
    pop  cx
    pop  ax
    ret

term_zero_block:
    push ax
    push es
    xor  ax, ax
    mov  es, ax
    xor  ax, ax
    rep  stosb
    pop  es
    pop  ax
    ret

term_append_string:
    push ax
    push di
    push es

    xor  ax, ax
    mov  es, ax
    mov  di, [term_resp_ptr]

.loop:
    lodsb
    test al, al
    jz   .done
    stosb
    jmp  .loop

.done:
    xor  al, al
    stosb
    dec  di
    mov  [term_resp_ptr], di

    pop  es
    pop  di
    pop  ax
    ret

term_append_char:
    push bx
    push di
    push es

    mov  bl, al
    xor  ax, ax
    mov  es, ax
    mov  di, [term_resp_ptr]
    mov  al, bl
    stosb
    xor  al, al
    stosb
    dec  di
    mov  [term_resp_ptr], di

    pop  es
    pop  di
    pop  bx
    ret

term_append_number:
    push ax
    push bx
    push cx
    push dx

    test ax, ax
    jge  .positive
    push ax
    mov  al, '-'
    call term_append_char
    pop  ax
    neg  ax

.positive:
    xor  cx, cx
    mov  bx, 10

.div:
    xor  dx, dx
    div  bx
    push dx
    inc  cx
    test ax, ax
    jnz  .div

.print:
    pop  dx
    mov  al, dl
    add  al, '0'
    call term_append_char
    loop .print

    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

term_skip_spaces:
    mov  al, [si]
    cmp  al, ' '
    jne  .done
    inc  si
    jmp  term_skip_spaces
.done:
    ret

term_append_help_group:
    push bx
    mov  bx, term_cmd_table
.loop:
    mov  di, [bx]
    test di, di
    jz   .done
    mov  al, [bx+6]
    test al, CMD_FLAG_HIDDEN
    jnz  .next
    test dl, CMD_FLAG_FS
    jnz  .fs_only
    test al, CMD_FLAG_FS
    jnz  .next
    jmp  .append
.fs_only:
    test al, CMD_FLAG_FS
    jz   .next
.append:
    mov  si, [bx+2]
    call term_append_string
    mov  al, 10
    call term_append_char
.next:
    add  bx, 7
    jmp  .loop
.done:
    pop  bx
    ret

term_load_errors:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x02
    mov  al, 1
    mov  ch, 0
    mov  cl, ERR_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, TERM_ERR_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

term_save_errors:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  cl, ERR_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, TERM_ERR_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

term_load_name:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x02
    mov  al, 1
    mov  ch, 0
    mov  cl, NAME_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, TERM_NAME_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

term_save_name:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  cl, NAME_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, TERM_NAME_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

fs_load:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x02
    mov  al, 1
    mov  ch, 0
    mov  cl, FS_HDR_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, FS_HDR_ADDR
    int  0x13

    mov  ah, 0x02
    mov  al, FS_TABLE_SECTORS
    mov  ch, 0
    mov  cl, FS_TABLE_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, FS_TABLE_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

fs_save:
    push ax
    push bx
    push cx
    push dx
    push es

    xor  ax, ax
    mov  es, ax

    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  cl, FS_HDR_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, FS_HDR_ADDR
    int  0x13

    mov  ah, 0x03
    mov  al, FS_TABLE_SECTORS
    mov  ch, 0
    mov  cl, FS_TABLE_SECTOR
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, FS_TABLE_ADDR
    int  0x13

    pop  es
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

fs_ensure_ready:
    mov  si, FS_HDR_ADDR
    mov  di, s_fs_signature
    call cmp_str
    je   .ok
    call fs_format
.ok:
    ret

fs_ensure_visual_layout:
    push si

    mov  si, s_visual_files
    call fs_ensure_root_dir

    mov  si, s_visual_desktop
    call fs_ensure_root_dir

    call fs_build_user_root_name
    mov  si, fs_user_root_name
    call fs_ensure_root_dir

    pop  si
    ret

fs_ensure_root_dir:
    push ax
    push dx
    push di

    xor  dl, dl
    call fs_find_dir_child
    jnc  .done
    call fs_find_free_entry
    jc   .done

    mov  byte [di], FS_FLAG_USED | FS_FLAG_DIR
    mov  byte [di+1], 0
    push di
    add  di, 4
    call fs_copy_zstr_to_dest
    pop  di
    call fs_save

.done:
    pop  di
    pop  dx
    pop  ax
    ret

fs_build_user_root_name:
    push ax
    push si
    push di

    mov  di, fs_user_root_name
    mov  si, TERM_NAME_ADDR
    mov  al, [si]
    cmp  al, 32
    jb   .default_name

.copy_name:
    lodsb
    test al, al
    jz   .suffix
    cmp  al, 32
    jb   .suffix
    stosb
    jmp  .copy_name

.default_name:
    mov  si, s_visual_user
.copy_default:
    lodsb
    test al, al
    jz   .suffix
    stosb
    jmp  .copy_default

.suffix:
    mov  si, s_visual_root_suffix
.copy_suffix:
    lodsb
    stosb
    test al, al
    jnz  .copy_suffix

    pop  di
    pop  si
    pop  ax
    ret

fs_format:
    mov  di, FS_HDR_ADDR
    mov  cx, 512
    call term_zero_block

    mov  di, FS_TABLE_ADDR
    mov  cx, FS_TABLE_SECTORS*512
    call term_zero_block

    mov  si, s_fs_signature
    mov  di, FS_HDR_ADDR
    call fs_copy_zstr_to_dest

    call fs_save
    ret

fs_copy_zstr_to_dest:
    push ax
    push es
    xor  ax, ax
    mov  es, ax
.loop:
    lodsb
    test al, al
    jz   .done
    stosb
    jmp  .loop
.done:
    mov  byte [di], 0
    pop  es
    pop  ax
    ret

fs_get_ptr_by_id:
    dec  al
    xor  ah, ah
    mov  bx, ax
    shl  bx, 5
    mov  di, FS_TABLE_ADDR
    add  di, bx
    ret

fs_find_free_entry:
    push cx
    mov  di, FS_TABLE_ADDR
    xor  al, al
    mov  cx, FS_MAX_ENTRIES
.loop:
    cmp  byte [di], 0
    je   .found
    add  di, FS_ENTRY_SIZE
    inc  al
    loop .loop
    stc
    pop  cx
    ret
.found:
    clc
    pop  cx
    ret

fs_clear_entry:
    push cx
    mov  cx, FS_ENTRY_SIZE
    call term_zero_block
    pop  cx
    ret

fs_find_dir_child:
    push bx
    push cx
    mov  di, FS_TABLE_ADDR
    xor  bx, bx
    mov  cx, FS_MAX_ENTRIES
.loop:
    mov  al, [di]
    test al, FS_FLAG_USED
    jz   .next
    test al, FS_FLAG_DIR
    jz   .next
    mov  al, [di+1]
    cmp  al, dl
    jne  .next
    push si
    push di
    add  di, 4
    call cmp_str
    pop  di
    pop  si
    je   .found
.next:
    add  di, FS_ENTRY_SIZE
    inc  bl
    loop .loop
    stc
    jmp  .done
.found:
    mov  al, bl
    inc  al
    clc
.done:
    pop  cx
    pop  bx
    ret

fs_find_file_child:
    push bx
    push bp
    push cx
    mov  bp, bx
    mov  di, FS_TABLE_ADDR
    xor  bx, bx
    mov  cx, FS_MAX_ENTRIES
.loop:
    mov  al, [di]
    test al, FS_FLAG_USED
    jz   .next
    test al, FS_FLAG_DIR
    jnz  .next
    mov  al, [di+1]
    cmp  al, dl
    jne  .next
    push si
    push di
    add  di, 4
    call cmp_str
    pop  di
    pop  si
    jne  .next
    push si
    push di
    mov  si, bp
    add  di, 16
    call cmp_str
    pop  di
    pop  si
    je   .found
.next:
    add  di, FS_ENTRY_SIZE
    inc  bl
    loop .loop
    stc
    jmp  .done
.found:
    mov  al, bl
    inc  al
    clc
.done:
    pop  cx
    pop  bp
    pop  bx
    ret

fs_delete_tree:
    push bx
    push cx
    push di
    mov  bh, al
    xor  bl, bl
    mov  di, FS_TABLE_ADDR
    mov  cx, FS_MAX_ENTRIES
.scan:
    mov  dl, [di]
    test dl, FS_FLAG_USED
    jz   .next
    mov  al, [di+1]
    cmp  al, bh
    jne  .next
    test dl, FS_FLAG_DIR
    jz   .clear_child
    push bx
    push cx
    push di
    mov  al, bl
    inc  al
    call fs_delete_tree
    pop  di
    pop  cx
    pop  bx
    jmp  .next
.clear_child:
    push bx
    push cx
    push di
    call fs_clear_entry
    pop  di
    pop  cx
    pop  bx
.next:
    add  di, FS_ENTRY_SIZE
    inc  bl
    loop .scan

    mov  al, bh
    call fs_get_ptr_by_id
    call fs_clear_entry

    pop  di
    pop  cx
    pop  bx
    ret

fs_refresh_path:
    push ax
    push di
    push si
    mov  di, TERM_DIR_ADDR
    mov  cx, TERM_DIR_SIZE
    call term_zero_block
    mov  al, [term_current_dir]
    test al, al
    jz   .done
    cmp  al, FS_MAX_ENTRIES
    ja   .reset_root
    call fs_get_ptr_by_id
    mov  al, [di]
    test al, FS_FLAG_USED
    jz   .reset_root
    test al, FS_FLAG_DIR
    jz   .reset_root
    mov  si, di
    add  si, 4
    mov  di, TERM_DIR_ADDR
    call fs_copy_zstr_to_dest
    jmp  .done
.reset_root:
    mov  byte [term_current_dir], 0
.done:
    pop  si
    pop  di
    pop  ax
    ret

term_log_error:
    push ax
    push bx
    push cx
    push di
    push es

    mov  bx, TERM_ERR_ADDR
    mov  cx, 8

.find:
    mov  al, [bx]
    test al, al
    jz   .slot
    add  bx, 32
    loop .find

    mov  si, TERM_ERR_ADDR + 32
    mov  di, TERM_ERR_ADDR
    mov  cx, 7 * 32
    xor  ax, ax
    mov  es, ax
    rep  movsb
    mov  bx, TERM_ERR_ADDR + 7*32

.slot:
    mov  di, bx
    mov  cx, 31

.copy:
    lodsb
    stosb
    test al, al
    jz   .done_copy
    loop .copy
    mov  byte [di], 0

.done_copy:
    call term_save_errors

    pop  es
    pop  di
    pop  cx
    pop  bx
    pop  ax
    ret

term_cmd_help:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    cmp  byte [term_current_dir], 0
    jne  .files

    mov  si, s_term_help_title
    call term_append_string
    xor  dl, dl
    call term_append_help_group
    mov  dl, CMD_FLAG_FS
    call term_append_help_group
    ret

.files:
    mov  si, s_term_helpf_title
    call term_append_string
    mov  dl, CMD_FLAG_FS
    call term_append_help_group
    ret

term_cmd_helpf:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_helpf_title
    call term_append_string
    mov  dl, CMD_FLAG_FS
    call term_append_help_group
    ret

term_cmd_pcname:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_pcname
    call term_append_string
    mov  si, TERM_NAME_ADDR
    call term_append_string
    ret

term_cmd_clear:
    mov  byte [term_resp_action], TERM_ACT_CLEAR
    ret

term_cmd_backcmd:
    mov  byte [term_resp_action], TERM_ACT_BACKCMD
    ret

term_cmd_errorlist:
    call term_load_errors
    mov  al, [TERM_ERR_ADDR]
    test al, al
    jnz  .show
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_no_errors
    call term_append_string
    ret

.show:
    mov  byte [term_resp_kind], TERM_RESP_ERRORLIST
    mov  si, s_term_error_title
    call term_append_string
    mov  al, 10
    call term_append_char
    mov  bx, TERM_ERR_ADDR
    mov  cx, 8
.lines:
    mov  al, [bx]
    test al, al
    jz   .done
    mov  si, s_term_bullet
    call term_append_string
    mov  si, bx
    call term_append_string
    mov  al, 10
    call term_append_char
    add  bx, 32
    loop .lines
.done:
    ret

term_cmd_shutdown:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_shutdown
    call term_append_string
    call poweroff_system
    ret

term_cmd_reboot:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_reboot
    call term_append_string
    call reboot_system
    ret

term_cmd_ls:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    xor  dl, dl
    call fs_list_current
    ret

term_cmd_ls_l:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_path
    call term_append_string
    call fs_append_current_path
    mov  al, 10
    call term_append_char
    mov  dl, 1
    call fs_list_current
    ret

term_cmd_cd:
    mov  si, term_upper_buf
    add  si, 2
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .parse
    mov  byte [term_current_dir], 0
    call fs_refresh_path
    ret
.parse:
    mov  di, fs_arg_name
    call term_parse_dir_token_to
    jc   .bad
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    call fs_find_dir_child
    jc   .missing
    mov  [term_current_dir], al
    call fs_refresh_path
    ret
.missing:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_cd_missing
    call term_append_string
    ret
.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_cd_usage
    call term_append_string
    ret

term_cmd_mkdir:
    mov  si, term_upper_buf
    add  si, 5
    call term_skip_spaces
    mov  di, fs_arg_name
    call term_parse_dir_token_to
    jc   .bad
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    call fs_find_dir_child
    jnc  .exists
    call fs_find_free_entry
    jc   .full
    mov  byte [di], FS_FLAG_USED | FS_FLAG_DIR
    mov  al, [term_current_dir]
    mov  [di+1], al
    push di
    mov  si, fs_arg_name
    add  di, 4
    call fs_copy_zstr_to_dest
    pop  di
    call fs_save
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_folder_created
    call term_append_string
    mov  si, fs_arg_name
    call term_append_string
    ret
.exists:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_folder_exists
    call term_append_string
    ret
.full:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_fs_full
    call term_append_string
    ret
.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_mkdir_usage
    call term_append_string
    ret

term_cmd_mkfile:
    mov  si, term_upper_buf
    add  si, 6
    call term_skip_spaces
    call term_parse_file_arg
    jc   .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    mov  bx, fs_arg_ext
    call fs_find_file_child
    jnc  .exists
    call fs_find_free_entry
    jc   .full
    mov  byte [di], FS_FLAG_USED
    mov  al, [term_current_dir]
    mov  [di+1], al
    push di
    mov  si, fs_arg_name
    add  di, 4
    call fs_copy_zstr_to_dest
    pop  di
    add  di, 16
    mov  si, fs_arg_ext
    call fs_copy_zstr_to_dest
    call fs_save
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_file_created
    call term_append_string
    mov  si, fs_arg_name
    call term_append_string
    mov  al, '.'
    call term_append_char
    mov  si, fs_arg_ext
    call term_append_string
    ret
.exists:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_file_exists
    call term_append_string
    ret
.full:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_fs_full
    call term_append_string
    ret
.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_mkfile_usage
    call term_append_string
    ret

term_cmd_rndir:
    mov  si, term_upper_buf
    add  si, 5
    call term_skip_spaces
    mov  di, fs_arg_name
    call term_parse_dir_token_to
    jc   .bad
    call term_skip_spaces
    cmp  byte [si], ','
    jne  .bad
    inc  si
    call term_skip_spaces
    mov  di, fs_arg_name2
    call term_parse_dir_token_to
    jc   .bad
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    call fs_find_dir_child
    jc   .missing
    push di
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name2
    call fs_find_dir_child
    jnc  .exists
    pop  di
    push di
    add  di, 4
    mov  cx, 12
    call term_zero_block
    pop  di
    add  di, 4
    mov  si, fs_arg_name2
    call fs_copy_zstr_to_dest
    call fs_save
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_rndir_done
    call term_append_string
    ret
.exists:
    pop  di
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_folder_exists
    call term_append_string
    ret
.missing:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_folder_missing
    call term_append_string
    ret
.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_rndir_usage
    call term_append_string
    ret

term_cmd_rm:
    mov  si, term_upper_buf
    add  si, 2
    call term_skip_spaces
    cmp  byte [si], 0
    je   .bad
    push si
    call term_arg_has_dot
    pop  si
    jc   .file
    mov  di, fs_arg_name
    call term_parse_dir_token_to
    jc   .bad
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    call fs_find_dir_child
    jc   .missing_folder
    call fs_delete_tree
    call fs_save
    call fs_refresh_path
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_removed
    call term_append_string
    mov  si, fs_arg_name
    call term_append_string
    ret
.file:
    call term_parse_file_arg
    jc   .bad
    mov  dl, [term_current_dir]
    mov  si, fs_arg_name
    mov  bx, fs_arg_ext
    call fs_find_file_child
    jc   .missing_file
    call fs_clear_entry
    call fs_save
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_removed
    call term_append_string
    mov  si, fs_arg_name
    call term_append_string
    mov  al, '.'
    call term_append_char
    mov  si, fs_arg_ext
    call term_append_string
    ret
.missing_folder:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_folder_missing
    call term_append_string
    ret
.missing_file:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_file_missing
    call term_append_string
    ret
.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_rm_usage
    call term_append_string
    ret

term_cmd_calc:
    mov  si, term_upper_buf
    add  si, 4
    call term_skip_spaces
    cmp  byte [si], 0
    je   .bad

    xor  ax, ax
.read_a:
    mov  cl, [si]
    cmp  cl, '0'
    jb   .got_a
    cmp  cl, '9'
    ja   .got_a
    sub  cl, '0'
    push cx
    mov  cx, 10
    mul  cx
    pop  cx
    xor  ch, ch
    add  ax, cx
    inc  si
    jmp  .read_a

.got_a:
    mov  [term_calc_a], ax

.find_op:
    mov  al, [si]
    cmp  al, ' '
    jne  .save_op
    inc  si
    jmp  .find_op

.save_op:
    test al, al
    jz   .bad
    mov  [term_calc_op], al
    inc  si

.skip_b_spaces:
    mov  al, [si]
    cmp  al, ' '
    jne  .read_b
    inc  si
    jmp  .skip_b_spaces

.read_b:
    xor  ax, ax
.read_b_loop:
    mov  cl, [si]
    cmp  cl, '0'
    jb   .got_b
    cmp  cl, '9'
    ja   .got_b
    sub  cl, '0'
    push cx
    mov  cx, 10
    mul  cx
    pop  cx
    xor  ch, ch
    add  ax, cx
    inc  si
    jmp  .read_b_loop

.got_b:
    mov  [term_calc_b], ax
    mov  al, [term_calc_op]
    cmp  al, '+'
    je   .add
    cmp  al, '-'
    je   .sub
    cmp  al, '*'
    je   .mul
    cmp  al, '/'
    je   .div
    jmp  .bad

.add:
    mov  ax, [term_calc_a]
    add  ax, [term_calc_b]
    jmp  .show

.sub:
    mov  ax, [term_calc_a]
    sub  ax, [term_calc_b]
    jmp  .show

.mul:
    mov  ax, [term_calc_a]
    mov  bx, [term_calc_b]
    imul bx
    jmp  .show

.div:
    cmp  word [term_calc_b], 0
    jne  .div_ok
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_divzero
    call term_append_string
    mov  si, s_term_divzero_log
    call term_log_error
    ret

.div_ok:
    mov  ax, [term_calc_a]
    cwd
    idiv word [term_calc_b]

.show:
    mov  byte [term_resp_kind], TERM_RESP_INFO
    call term_append_number
    ret

.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_calc_bad
    call term_append_string
    ret

term_cmd_renamepc:
    mov  si, term_raw_buf
    add  si, 8
    call term_skip_spaces
    cmp  byte [si], 0
    je   .bad

    mov  di, TERM_NAME_ADDR
    mov  cx, 16
    call term_zero_block

    mov  di, TERM_NAME_ADDR
    mov  bx, 4
    push es
    xor  ax, ax
    mov  es, ax

.copy:
    lodsb
    test al, al
    jz   .saved
    cmp  al, ' '
    je   .saved
    stosb
    dec  bx
    jnz  .copy

.saved:
    mov  byte [di], 0
    pop  es
    call term_save_name
    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_rename_done
    call term_append_string
    ret

.bad:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_rename_usage
    call term_append_string
    ret

term_cmd_delete_sys:
    mov  si, term_upper_buf
    add  si, 10
    call term_skip_spaces

    mov  di, c_term_yes
    call cmp_str
    jne  .need_confirm

    mov  di, 0xC000
    mov  cx, 512
    call term_zero_block

    mov  si, 18
    mov  di, 32

.wipe:
    mov  ax, si
    mov  cl, al
    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  dh, 0
    mov  dl, [boot_drive_val]
    mov  bx, 0xC000
    int  0x13
    jc   .disk_error
    inc  si
    dec  di
    jnz  .wipe

    mov  byte [term_resp_kind], TERM_RESP_INFO
    mov  si, s_term_deleted
    call term_append_string
    mov  byte [term_resp_action], TERM_ACT_BACKCMD
    ret

.disk_error:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_delete_error
    call term_append_string
    ret

.need_confirm:
    mov  byte [term_resp_kind], TERM_RESP_ERROR
    mov  si, s_term_delete_usage
    call term_append_string
    ret

term_parse_dir_token_to:
    push ax
    push bx
    push cx
    push es
    mov  bx, di
    mov  cx, 13
    call term_zero_block
    mov  di, bx
    xor  bx, bx
    xor  ax, ax
    mov  es, ax
.loop:
    mov  al, [si]
    test al, al
    jz   .done
    cmp  al, ' '
    je   .done
    cmp  al, ','
    je   .done
    cmp  al, '.'
    je   .error
    cmp  al, '/'
    je   .error
    cmp  al, '\'
    je   .error
    cmp  bl, 12
    jae  .error
    stosb
    inc  si
    inc  bl
    jmp  .loop
.done:
    cmp  bl, 0
    je   .error
    mov  byte [di], 0
    clc
    jmp  .ret
.error:
    stc
.ret:
    pop  es
    pop  cx
    pop  bx
    pop  ax
    ret

term_parse_file_arg:
    push ax
    push bx
    push cx
    push es
    mov  di, fs_arg_name
    mov  cx, 13
    call term_zero_block
    mov  di, fs_arg_ext
    mov  cx, 4
    call term_zero_block
    mov  di, fs_arg_name
    xor  bx, bx
    xor  ax, ax
    mov  es, ax
.name_loop:
    mov  al, [si]
    test al, al
    jz   .error
    cmp  al, ' '
    je   .error
    cmp  al, ','
    je   .error
    cmp  al, '.'
    je   .dot
    cmp  al, '/'
    je   .error
    cmp  al, '\'
    je   .error
    cmp  bl, 12
    jae  .error
    stosb
    inc  si
    inc  bl
    jmp  .name_loop
.dot:
    cmp  bl, 0
    je   .error
    mov  byte [di], 0
    inc  si
    mov  di, fs_arg_ext
    xor  bx, bx
.ext_loop:
    mov  al, [si]
    test al, al
    jz   .ext_done
    cmp  al, ' '
    je   .ext_done
    cmp  al, ','
    je   .error
    cmp  al, '.'
    je   .error
    cmp  al, '/'
    je   .error
    cmp  al, '\'
    je   .error
    cmp  bl, 3
    jae  .error
    stosb
    inc  si
    inc  bl
    jmp  .ext_loop
.ext_done:
    cmp  bl, 0
    je   .error
    mov  byte [di], 0
    call term_skip_spaces
    cmp  byte [si], 0
    jne  .error
    clc
    jmp  .ret
.error:
    stc
.ret:
    pop  es
    pop  cx
    pop  bx
    pop  ax
    ret

term_arg_has_dot:
.loop:
    mov  ah, [si]
    test ah, ah
    jz   .no
    cmp  ah, ' '
    je   .no
    cmp  ah, '.'
    je   .yes
    inc  si
    jmp  .loop
.yes:
    stc
    ret
.no:
    clc
    ret

fs_append_entry_name:
    push si
    push ax
    mov  si, di
    add  si, 4
    call term_append_string
    mov  al, [di]
    test al, FS_FLAG_DIR
    jnz  .done
    cmp  byte [di+16], 0
    jz   .done
    mov  al, '.'
    call term_append_char
    mov  si, di
    add  si, 16
    call term_append_string
.done:
    pop  ax
    pop  si
    ret

fs_append_current_path:
    mov  si, s_term_filesys_root
    call term_append_string
    cmp  byte [TERM_DIR_ADDR], 0
    je   .done
    mov  al, '\'
    call term_append_char
    mov  si, TERM_DIR_ADDR
    call term_append_string
.done:
    ret

fs_list_current:
    push ax
    push cx
    push di
    mov  di, FS_TABLE_ADDR
    mov  cx, FS_MAX_ENTRIES
    mov  byte [term_list_found], 0
.loop:
    mov  al, [di]
    test al, FS_FLAG_USED
    jz   .next
    mov  al, [di+1]
    cmp  al, [term_current_dir]
    jne  .next
    mov  byte [term_list_found], 1
    cmp  dl, 0
    je   .short
    mov  al, [di]
    test al, FS_FLAG_DIR
    jz   .long_file
    mov  si, s_term_dir_tag
    call term_append_string
    jmp  .append_name
.long_file:
    mov  si, s_term_file_tag
    call term_append_string
    jmp  .append_name
.short:
    call fs_append_entry_name
    mov  al, [di]
    test al, FS_FLAG_DIR
    jz   .newline
    mov  al, '/'
    call term_append_char
    jmp  .newline
.append_name:
    call fs_append_entry_name
.newline:
    mov  al, 10
    call term_append_char
.next:
    add  di, FS_ENTRY_SIZE
    loop .loop
    cmp  byte [term_list_found], 0
    jne  .done
    mov  si, s_term_empty
    call term_append_string
.done:
    pop  di
    pop  cx
    pop  ax
    ret

; =======================
; DISK TEST
; =======================
disk_test:
    mov  byte [v_attr], ATTR_WHITE
    mov  si, s_drive_msg
    call puts
    xor  ax, ax
    mov  al, [BOOT_DRIVE]
    call print_hex_byte
    call newline

    mov  si, test_data
    mov  di, 0x9000
.copy:
    lodsb
    mov  [di], al
    inc  di
    test al, al
    jnz  .copy

    mov  byte [v_attr], ATTR_WHITE
    mov  si, s_writing
    call puts
    call newline

    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  cl, 6
    mov  dh, 0
    mov  dl, [BOOT_DRIVE]
    mov  bx, 0x9000
    int  0x13
    jc   .write_err

    mov  di, 0x9000
    mov  cx, 64
    xor  al, al
    rep  stosb

    mov  byte [v_attr], ATTR_WHITE
    mov  si, s_reading
    call puts
    call newline

    mov  ah, 0x02
    mov  al, 1
    mov  ch, 0
    mov  cl, 6
    mov  dh, 0
    mov  dl, [BOOT_DRIVE]
    mov  bx, 0x9000
    int  0x13
    jc   .read_err

    mov  byte [v_attr], ATTR_GREEN
    mov  si, s_result
    call puts
    mov  si, 0x9000
    call puts
    call newline
    ret

.write_err:
    mov  byte [v_attr], ATTR_RED
    mov  si, s_disk_werr
    call puts
    mov  al, ah
    call print_hex_byte
    call newline
    ret

.read_err:
    mov  byte [v_attr], ATTR_RED
    mov  si, s_disk_rerr
    call puts
    mov  al, ah
    call print_hex_byte
    call newline
    ret

poweroff_system:
    cli

    mov  ax, 0x5301
    xor  bx, bx
    int  0x15

    mov  ax, 0x530E
    xor  bx, bx
    mov  cx, 0x0102
    int  0x15

    mov  ax, 0x5307
    mov  bx, 0x0001
    mov  cx, 0x0003
    int  0x15

    mov  dx, 0x0604
    mov  ax, 0x2000
    out  dx, ax

    mov  dx, 0xB004
    mov  ax, 0x2000
    out  dx, ax

    mov  dx, 0x4004
    mov  ax, 0x3400
    out  dx, ax

.hang:
    hlt
    jmp  .hang

reboot_system:
    cli
    mov  al, 0xFE
    out  0x64, al
    int  0x19
    jmp  0xFFFF:0x0000

; =======================
; PRINT HEX BYTE
; =======================
print_hex_byte:
    push ax
    push bx
    mov  bl, al
    shr  al, 4
    and  al, 0x0F
    add  al, '0'
    cmp  al, '9'
    jbe  .hi_ok
    add  al, 7
.hi_ok:
    mov  ah, [v_attr]
    call putc
    mov  al, bl
    and  al, 0x0F
    add  al, '0'
    cmp  al, '9'
    jbe  .lo_ok
    add  al, 7
.lo_ok:
    mov  ah, [v_attr]
    call putc
    pop  bx
    pop  ax
    ret

; =======================
; UTILS
; =======================
do_prompt:
    mov  word [v_len], 0
    mov  word [v_cur], 0
    mov  byte [v_attr], ATTR_CYAN
    mov  si, s_prompt
    call puts
    ret

kbd_read:
    mov  ah, 0x10
    int  0x16

    cmp  al, 0xE0
    jne  .check_zero
    cmp  ah, 0x35
    je   .slash
    cmp  ah, 0x1C
    je   .enter
    xor  al, al
    ret

.check_zero:
    test al, al
    jnz  .done

    cmp  ah, 0x47
    je   .kp7
    cmp  ah, 0x48
    je   .kp8
    cmp  ah, 0x49
    je   .kp9
    cmp  ah, 0x4A
    je   .minus
    cmp  ah, 0x4B
    je   .kp4
    cmp  ah, 0x4C
    je   .kp5
    cmp  ah, 0x4D
    je   .kp6
    cmp  ah, 0x4E
    je   .plus
    cmp  ah, 0x4F
    je   .kp1
    cmp  ah, 0x50
    je   .kp2
    cmp  ah, 0x51
    je   .kp3
    cmp  ah, 0x52
    je   .kp0
    cmp  ah, 0x53
    je   .dot
    cmp  ah, 0x37
    je   .star
    cmp  ah, 0x35
    je   .slash
    ret

.kp7:
    mov  al, '7'
    ret
.kp8:
    mov  al, '8'
    ret
.kp9:
    mov  al, '9'
    ret
.kp4:
    mov  al, '4'
    ret
.kp5:
    mov  al, '5'
    ret
.kp6:
    mov  al, '6'
    ret
.kp1:
    mov  al, '1'
    ret
.kp2:
    mov  al, '2'
    ret
.kp3:
    mov  al, '3'
    ret
.kp0:
    mov  al, '0'
    ret
.dot:
    mov  al, '.'
    ret
.plus:
    mov  al, '+'
    ret
.minus:
    mov  al, '-'
    ret
.star:
    mov  al, '*'
    ret
.slash:
    mov  al, '/'
    ret
.enter:
    mov  al, 13
.done:
    ret

puts:
    push si
.loop:
    lodsb
    test al, al
    jz   .done
    cmp  al, 10
    je   .nl
    mov  ah, [v_attr]
    call putc
    jmp  .loop
.nl:
    call newline
    jmp  .loop
.done:
    pop  si
    ret

putc:
    call putc_raw
    inc  byte [v_col]
    cmp  byte [v_col], 80
    jb   .ok
    mov  byte [v_col], 0
    inc  byte [v_row]
    call scroll_check
.ok:
    call move_cur
    ret

putc_raw:
    push bx
    push cx
    push es
    mov  bx, 0xB800
    mov  es, bx
    xor  bx, bx
    xor  cx, cx
    mov  bl, [v_row]
    mov  cx, bx
    shl  cx, 6
    shl  bx, 4
    add  bx, cx
    xor  cx, cx
    mov  cl, [v_col]
    add  bx, cx
    shl  bx, 1
    mov  ah, [v_attr]
    mov  [es:bx],   al
    mov  [es:bx+1], ah
    pop  es
    pop  cx
    pop  bx
    ret

newline:
    mov  byte [v_col], 0
    inc  byte [v_row]
    call scroll_check
    call move_cur
    ret

scroll_check:
    cmp  byte [v_row], 25
    jb   .ok
    call scroll_up
    mov  byte [v_row], 24
.ok:
    ret

scroll_up:
    push ax
    push bx
    push cx
    push dx
    mov  ah, 0x06
    mov  al, 1
    xor  cx, cx
    mov  dx, 0x184F
    mov  bh, 0x07
    int  0x10
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

move_cur:
    push ax
    push bx
    push dx
    mov  ah, 0x02
    xor  bh, bh
    mov  dh, [v_row]
    mov  dl, [v_col]
    int  0x10
    pop  dx
    pop  bx
    pop  ax
    ret

cls:
    push es
    push di
    push cx
    push ax
    mov  ax, 0xB800
    mov  es, ax
    xor  di, di
    mov  cx, 80*25
    mov  ax, 0x0700
    rep  stosw
    pop  ax
    pop  cx
    pop  di
    pop  es
    ret

cmp_str:
    push si
    push di
    push ax
.loop:
    mov  al, [si]
    cmp  al, [di]
    jne  .neq
    test al, al
    jz   .eq
    inc  si
    inc  di
    jmp  .loop
.eq:
    pop  ax
    pop  di
    pop  si
    xor  ax, ax
    ret
.neq:
    pop  ax
    pop  di
    pop  si
    mov  ax, 1
    or   ax, ax
    ret

; =======================
; DATA
; =======================
v_row  db 0
v_col  db 0
v_attr db ATTR_WHITE
v_len  dw 0
v_buf  times 64 db 0
v_tmp  times 64 db 0
v_cur  dw 0

c_hello    db 'HELLO',0
c_help     db 'HELP',0
c_clear    db 'CLEAR',0
c_restart  db 'RESTART',0
c_reboot   db 'REBOOT',0
c_shutdown db 'SHUTDOWN',0
c_disk     db 'DISK',0
c_switchos db 'OPENVISUAL',0

s_prompt   db 'cmd> ',0
s_sys      db 'sys> ',0

s_banner   db '<<Krust core>>',10,'KrustOS v0.1',10,'type "help" for commands',10,0
s_hello    db 'Hello, World!',0

; FIX: каждая строка заканчивается ,0 !
s_help     db 'Commands:',10
           db '  hello              - greeting',10
           db '  help               - this help',10
           db '  clear              - clear screen',10
           db '  restart            - reboot',10
           db '  reboot             - reboot',10
           db '  shutdown           - power off',10
           db '  disk               - disk r/w test',10
           db '  openvisual         - start KrustOSvisual',10,0

s_restart   db 'Rebooting...',0
s_shutdown  db 'Powering off...',0
s_switching  db 'Switching to KrustOSvisual...',0
s_loading1   db 'Switching to KrustOSvisual...',0
s_loading2   db '[ Loading...          ]',0
s_loading3   db 'Done! Welcome back!',0
s_load_err   db 'Load error! Is KrustOSvisual.bin on disk?',0
s_err1      db 'Error: "',0
s_err2      db '" not found. type "help"',0
s_disktest  db 'Running disk test...',0
s_writing   db 'Writing sector 6...',0
s_reading   db 'Reading sector 6...',0
s_result    db 'Read back: ',0
s_drive_msg db 'Boot drive: 0x',0
s_disk_werr db 'Write error! Code: 0x',0
s_disk_rerr db 'Read error! Code: 0x',0

term_load_dap:
    db 16
    db 0
    dw 32          ; сколько секторов читать
    dw 0x0000      ; куда (offset)
    dw 0x2000      ; куда (segment)
    dq 17          ; LBA, куда run.bat пишет KrustOSvisual.bin

term_cmd_table:
    dw c_term_help,       d_term_help,       term_cmd_help
    db 0
    dw c_term_helpf,      d_term_helpf,      term_cmd_helpf
    db CMD_FLAG_FS
    dw c_term_clear,      d_term_clear,      term_cmd_clear
    db 0
    dw c_term_calc,       d_term_calc,       term_cmd_calc
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD
    dw c_term_pcname,     d_term_pcname,     term_cmd_pcname
    db 0
    dw c_term_ls_l,       d_term_ls_l,       term_cmd_ls_l
    db CMD_FLAG_FS
    dw c_term_ls,         d_term_ls,         term_cmd_ls
    db CMD_FLAG_FS
    dw c_term_cd,         d_term_cd,         term_cmd_cd
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD | CMD_FLAG_FS
    dw c_term_mkdir,      d_term_mkdir,      term_cmd_mkdir
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD | CMD_FLAG_FS
    dw c_term_mkfile,     d_term_mkfile,     term_cmd_mkfile
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD | CMD_FLAG_FS
    dw c_term_rndir,      d_term_rndir,      term_cmd_rndir
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD | CMD_FLAG_FS
    dw c_term_rm,         d_term_rm,         term_cmd_rm
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD | CMD_FLAG_FS
    dw c_term_errorlist,  d_term_errorlist,  term_cmd_errorlist
    db 0
    dw c_term_renamepc,   d_term_renamepc,   term_cmd_renamepc
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD
    dw c_term_delete_sys, d_term_delete_sys, term_cmd_delete_sys
    db CMD_FLAG_PREFIX | CMD_FLAG_WORD
    dw c_term_backcmd,    d_term_backcmd,    term_cmd_backcmd
    db 0
    dw c_term_reboot,     d_term_reboot,     term_cmd_reboot
    db 0
    dw c_term_shutdown,   d_term_shutdown,   term_cmd_shutdown
    db 0
    dw 0, 0, 0
    db 0

c_term_help       db 'HELP',0
c_term_helpf      db 'HELPF',0
c_term_clear      db 'CLEAR',0
c_term_calc       db 'CALC',0
c_term_pcname     db 'PCNAME',0
c_term_ls         db 'LS',0
c_term_ls_l       db 'LS-L',0
c_term_cd         db 'CD',0
c_term_mkdir      db 'MKDIR',0
c_term_mkfile     db 'MKFILE',0
c_term_rndir      db 'RNDIR',0
c_term_rm         db 'RM',0
c_term_errorlist  db 'ERRORLIST',0
c_term_renamepc   db 'RENAMEPC',0
c_term_delete_sys db 'DELETE SYS',0
c_term_backcmd    db 'BACKCMD',0
c_term_reboot     db 'REBOOT',0
c_term_shutdown   db 'SHUTDOWN',0
c_term_yes        db 'YES',0

d_term_help       db '  help         - show general commands',0
d_term_helpf      db '  helpf        - show file system commands',0
d_term_clear      db '  clear        - clear screen',0
d_term_calc       db '  calc X+Y     - calculate expression',0
d_term_pcname     db '  pcname       - show current PC name',0
d_term_ls         db '  ls           - list current folder',0
d_term_ls_l       db '  ls-l         - list current folder with types',0
d_term_cd         db '  cd <folder>  - open folder, or cd for root',0
d_term_mkdir      db '  mkdir <name> - create a folder',0
d_term_mkfile     db '  mkfile <name.ext> - create a file entry',0
d_term_rndir      db '  rndir <old>,<new> - rename a folder',0
d_term_rm         db '  rm <name>    - delete file or folder recursively',0
d_term_errorlist  db '  errorlist    - error log',0
d_term_renamepc   db '  renamepc <name> - rename PC',0
d_term_delete_sys db '  delete sys   - delete TermOS',0
d_term_backcmd    db '  backcmd      - KernelCMD',0
d_term_reboot     db '  reboot       - reboot system',0
d_term_shutdown   db '  shutdown     - power off',0

s_term_help_title   db 'Available commands:',10,0
s_term_helpf_title  db 'File system commands:',10,0
s_term_pcname       db 'Current PC name is: ',0
s_term_unknown1     db 'Unknown: "',0
s_term_unknown2     db '" (try "help")',0
s_term_error_title  db 'Errors in last sessions:',0
s_term_no_errors    db 'No errors found!',0
s_term_bullet       db '  - ',0
s_term_reboot      db 'Rebooting...',10,'See you soon!',0
s_term_shutdown     db 'Powering off...',10,'Bye!',0
s_term_path         db 'Path: ',0
s_term_empty        db '  (empty)',0
s_term_dir_tag      db '[DIR]  ',0
s_term_file_tag     db '[FILE] ',0
s_term_cd_usage     db 'Usage: cd <folder> or cd',0
s_term_cd_missing   db 'Folder not found.',0
s_term_mkdir_usage  db 'Usage: mkdir <folder>',0
s_term_mkfile_usage db 'Usage: mkfile <name.ext>',0
s_term_rndir_usage  db 'Usage: rndir <old>,<new>',0
s_term_rm_usage     db 'Usage: rm <folder> or rm <name.ext>',0
s_term_fs_full      db 'File system is full.',0
s_term_fs_only      db 'Only file system commands and helpf are allowed inside folders.',0
s_term_folder_created db 'Folder created: ',0
s_term_file_created   db 'File created: ',0
s_term_removed        db 'Removed: ',0
s_term_folder_exists  db 'Folder already exists.',0
s_term_file_exists    db 'File already exists.',0
s_term_folder_missing db 'Folder not found.',0
s_term_file_missing   db 'File not found.',0
s_term_rndir_done     db 'Folder renamed.',0
s_term_divzero      db 'ERROR: divide by zero',0
s_term_divzero_log  db 'divide by zero',0
s_term_calc_bad     db 'ERROR: use calc X+Y',0
s_term_rename_done  db 'Name updated!',0
s_term_rename_usage db 'Usage: renamepc <name> (max 4 chars)',0
s_term_deleted      db 'Visual shell removed. Returning to KernelCMD.',0
s_term_delete_usage db 'Confirmation required: delete sys yes',0
s_term_delete_error db 'Delete failed while writing disk.',0
s_term_filesys_root db 'filesys',0
s_fs_signature      db 'KFS1',0
s_visual_files      db 'FILES',0
s_visual_desktop    db 'DESKTOP',0
s_visual_user       db 'USER',0
s_visual_root_suffix db '-ROOT',0

term_resp_kind   db 0
term_resp_action db 0
term_resp_ptr    dw TERM_RESP_ADDR
term_raw_buf     times 64 db 0
term_upper_buf   times 64 db 0
term_current_dir db 0
term_list_found  db 0
term_calc_a      dw 0
term_calc_b      dw 0
term_calc_op     db 0
fs_arg_name      times 13 db 0
fs_arg_ext       times 4 db 0
fs_arg_name2     times 13 db 0
fs_path_nodes    times 16 db 0
fs_user_root_name times 16 db 0

test_data      db 'KRUST WORKS!',0
boot_drive_val db 0x80
