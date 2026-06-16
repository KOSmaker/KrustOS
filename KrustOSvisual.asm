[org 0]
[bits 16]

NAME_ADDR equ 0xD000
DIR_ADDR  equ 0xD200
RESP_ADDR equ 0xD300
SETTINGS_MAGIC_ADDR equ NAME_ADDR + 16
SETTINGS_GMT_ADDR   equ NAME_ADDR + 20
NAME_SECTOR equ 50
BOOT_DRIVE_ADDR equ 0x7A00

KAPI_FN_EXEC equ 0x00
KAPI_FN_INIT equ 0x01

TERM_RESP_NONE  equ 0
TERM_RESP_INFO  equ 1
TERM_RESP_ERROR equ 2

TERM_ACT_NONE    equ 0
TERM_ACT_CLEAR   equ 1
TERM_ACT_BACKCMD equ 2
TERM_ACT_HALT    equ 3

WINDOW_DESKTOP equ 0
WINDOW_TERM    equ 1
WINDOW_FILES   equ 2

PROMPT_NONE    equ 0
PROMPT_MKDIR   equ 1
PROMPT_MKFILE  equ 2
PROMPT_RNDIR   equ 3

SETUP_NONE equ 0
SETUP_NAME equ 1
SETUP_GMT  equ 2

SCREEN_W equ 320
SCREEN_H equ 200
TEXT_CELL_H equ 8
TEXT_DEFAULT_CELL_W equ 8
TEXT_DEFAULT_GLYPH_W equ 6
TEXT_DEFAULT_GLYPH_H equ 7
TEXT_TERM_CELL_W equ 9
TEXT_TERM_GLYPH_W equ 8
TEXT_TERM_GLYPH_H equ 7
TEXT_TERMINAL_CELL_W equ 7
TEXT_TERMINAL_CELL_H equ 7
TEXT_TERMINAL_GLYPH_W equ 6
TEXT_TERMINAL_GLYPH_H equ 7

TERM_TEXT_COL equ 13
TERM_OUTPUT_ROW equ 5
TERM_PROMPT_ROW equ 21
TERM_HELP_ROW equ 23

FILES_TEXT_COL equ 10
FILES_TITLE_COL equ 12
FILES_FIRST_ROW equ 6
FILES_PATH_ROW equ 18
FILES_HELP_ROW equ 19

FOOTER_RIGHT_COL equ 35

start:
    cli
    mov  ax, cs
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0xFFFE
    sti

    call set_video_mode
    call init_font_renderer
    call kernel_init_state
    call zero_runtime_state
    call load_user_name_cache
    call init_mouse_support
    call set_default_status
    call clear_term_output
    call load_settings_cache
    call start_kruststart_if_needed
    call render_screen
    mov  byte [render_pending], 0

main_loop:
    call poll_mouse
    call poll_shift_exit
    call poll_clock_tick
    cmp  byte [render_pending], 0
    je   .input
    call render_screen
    mov  byte [render_pending], 0
.input:
    call kbd_read
    test ax, ax
    jz   main_loop
    call handle_key
    mov  byte [render_pending], 1
    jmp  main_loop

set_video_mode:
    mov  ax, 0x0013
    int  0x10
    mov  ah, 0x01
    mov  ch, 0x20
    mov  cl, 0
    int  0x10
    ret

init_font_renderer:
    push ax
    push bx
    push bp
    push es

    mov  ax, 0x1130
    mov  bh, 0x03
    int  0x10
    mov  [font_seg], es
    mov  [font_off], bp

    pop  es
    pop  bp
    pop  bx
    pop  ax
    ret

zero_runtime_state:
    push ax
    push cx
    push di

    mov  ax, cs
    mov  es, ax
    xor  ax, ax

    mov  di, runtime_state_begin
    mov  cx, runtime_state_end - runtime_state_begin
    rep  stosb

    mov  word [cursor_x], 24
    mov  word [cursor_y], 34
    mov  byte [active_window], WINDOW_DESKTOP
    mov  byte [modal_action], PROMPT_NONE
    mov  byte [term_kind], TERM_RESP_NONE
    mov  byte [term_action], TERM_ACT_NONE
    mov  byte [file_item_count], 0
    mov  byte [file_sel], 0
    mov  byte [term_input_len], 0
    mov  byte [modal_len], 0
    mov  byte [setup_step], SETUP_NONE
    mov  byte [gmt_offset], 0
    mov  byte [clock_last_min], 0xFF
    mov  byte [text_cell_h], TEXT_CELL_H
    mov  byte [text_cell_w], TEXT_DEFAULT_CELL_W
    mov  byte [text_glyph_w], TEXT_DEFAULT_GLYPH_W
    mov  byte [text_glyph_h], TEXT_DEFAULT_GLYPH_H
    mov  byte [text_compact], 0
    mov  byte [render_pending], 1

    pop  di
    pop  cx
    pop  ax
    ret

render_screen:
    call set_text_metrics_default
    call draw_background
    call draw_desktop_icons
    call draw_clock_widget

    mov  al, [active_window]
    cmp  al, WINDOW_TERM
    jne  .check_files
    call draw_terminal_window
.check_files:
    mov  al, [active_window]
    cmp  al, WINDOW_FILES
    jne  .footer
    call set_text_metrics_default
    call draw_files_window

.footer:
    call set_text_metrics_default
    call draw_footer
    mov  al, [modal_action]
    cmp  al, PROMPT_NONE
    je   .cursor
    call set_text_metrics_default
    call draw_modal
.cursor:
    call draw_cursor
    ret

draw_background:
    mov  di, 0
    mov  bx, 0
    mov  cx, SCREEN_W
    mov  dx, SCREEN_H
    mov  al, 0x01
    call fill_rect

    mov  di, 0
    mov  bx, 0
    mov  cx, SCREEN_W
    mov  dx, 24
    mov  al, 0x19
    call fill_rect

    mov  di, 0
    mov  bx, 180
    mov  cx, SCREEN_W
    mov  dx, 20
    mov  al, 0x08
    call fill_rect

    mov  di, 212
    mov  bx, 36
    mov  cx, 88
    mov  dx, 80
    mov  al, 0x11
    call fill_rect

    mov  dh, 0
    mov  dl, 1
    mov  bl, 0x0F
    mov  si, s_title
    call print_string_at

    mov  dh, 0
    mov  dl, 22
    mov  bl, 0x0B
    mov  si, s_subtitle
    call print_string_at
    ret

draw_desktop_icons:
    call draw_terminal_icon
    call draw_files_icon
    ret

draw_clock_widget:
    call update_clock_text
    call set_text_metrics_default

    mov  dh, 5
    mov  dl, 27
    mov  bl, 0x0F
    mov  si, s_clock_title
    call print_string_at

    mov  dh, 7
    mov  dl, 27
    mov  bl, 0x0E
    mov  si, clock_text
    call print_string_at

    mov  dh, 9
    mov  dl, 27
    mov  bl, 0x0B
    mov  si, gmt_text
    call print_string_at
    ret

draw_terminal_icon:
    mov  di, 18
    mov  bx, 40
    mov  cx, 38
    mov  dx, 30
    mov  al, 0x2A
    call fill_rect

    mov  di, 24
    mov  bx, 45
    mov  cx, 26
    mov  dx, 15
    mov  al, 0x00
    call fill_rect

    mov  di, 27
    mov  bx, 49
    mov  cx, 7
    mov  dx, 2
    mov  al, 0x0A
    call fill_rect

    mov  dh, 9
    mov  dl, 2
    mov  bl, 0x0F
    mov  si, s_icon_term
    call print_string_at
    ret

draw_files_icon:
    mov  di, 18
    mov  bx, 92
    mov  cx, 38
    mov  dx, 30
    mov  al, 0x2E
    call fill_rect

    mov  di, 25
    mov  bx, 99
    mov  cx, 24
    mov  dx, 14
    mov  al, 0x0E
    call fill_rect

    mov  di, 25
    mov  bx, 95
    mov  cx, 10
    mov  dx, 4
    mov  al, 0x0E
    call fill_rect

    mov  dh, 16
    mov  dl, 2
    mov  bl, 0x0F
    mov  si, s_icon_files
    call print_string_at
    ret

draw_terminal_window:
    call set_text_metrics_terminal
    mov  di, 84
    mov  bx, 20
    mov  cx, 234
    mov  dx, 154
    mov  al, 0x07
    call fill_rect

    mov  di, 86
    mov  bx, 22
    mov  cx, 230
    mov  dx, 150
    mov  al, 0x00
    call fill_rect

    mov  di, 86
    mov  bx, 22
    mov  cx, 230
    mov  dx, 10
    mov  al, 0x18
    call fill_rect

    mov  dh, 3
    mov  dl, TERM_TEXT_COL
    mov  bl, 0x0F
    mov  si, s_term_title
    call print_string_at

    mov  dh, TERM_OUTPUT_ROW
    mov  dl, TERM_TEXT_COL
    mov  bl, 0x0A
    mov  si, term_output
    mov  cx, 0x1020
    call print_wrapped_block

    mov  dh, TERM_PROMPT_ROW
    mov  dl, TERM_TEXT_COL
    mov  bl, 0x0E
    mov  si, user_name_cache
    call print_string_at

    mov  dh, TERM_PROMPT_ROW
    mov  dl, TERM_TEXT_COL
    add  dl, [user_prompt_len]
    mov  bl, 0x0E
    mov  si, s_user_prompt_suffix
    call print_string_at

    mov  dh, TERM_PROMPT_ROW
    mov  dl, TERM_TEXT_COL
    add  dl, [user_prompt_len]
    inc  dl
    mov  bl, 0x0F
    call draw_term_input_block

    mov  dh, TERM_HELP_ROW
    mov  dl, TERM_TEXT_COL
    mov  bl, 0x08
    mov  si, s_term_help
    call print_string_at
    ret

draw_files_window:
    call set_text_metrics_term
    mov  di, 84
    mov  bx, 16
    mov  cx, 234
    mov  dx, 158
    mov  al, 0x07
    call fill_rect

    mov  di, 86
    mov  bx, 18
    mov  cx, 230
    mov  dx, 154
    mov  al, 0x1C
    call fill_rect

    mov  di, 86
    mov  bx, 18
    mov  cx, 230
    mov  dx, 14
    mov  al, 0x31
    call fill_rect

    mov  dh, 3
    mov  dl, FILES_TITLE_COL
    mov  bl, 0x0F
    mov  si, s_files_title
    call print_string_at

    call draw_files_items

    mov  dh, FILES_PATH_ROW
    mov  dl, FILES_TEXT_COL
    mov  bl, 0x0F
    mov  si, files_text
    call print_line_at

    mov  dh, FILES_HELP_ROW
    mov  dl, FILES_TEXT_COL
    mov  bl, 0x08
    mov  si, s_files_help
    mov  cx, 0x0218
    call print_wrapped_block
    ret

draw_files_items:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor  bx, bx
    xor  cx, cx
    mov  cl, [file_item_count]
    jcxz .done

.loop:
    mov  bh, bl
    mov  al, [file_sel]
    cmp  bh, al
    jne  .plain
    push bx
    mov  di, 90
    xor  ax, ax
    mov  al, bh
    shl  ax, 3
    add  ax, 48
    mov  bx, ax
    mov  cx, 210
    mov  dx, 8
    mov  al, 0x3A
    call fill_rect
    pop  bx
    mov  dh, FILES_FIRST_ROW
    add  dh, bh
    jmp  .draw

.plain:
    mov  dh, FILES_FIRST_ROW
    add  dh, bh

.draw:
    mov  dl, FILES_TEXT_COL
    xor  ax, ax
    mov  al, bh
    shl  ax, 1
    mov  si, ax
    mov  si, [file_item_offsets + si]
    mov  bl, 0x0F
    call print_line_at

    mov  bl, bh
    inc  bl
    cmp  bl, [file_item_count]
    jb   .loop

.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

draw_footer:
    call set_text_metrics_term

    push ax
    push cx
    push si

    mov  si, status_text
    xor  cx, cx
.count:
    lodsb
    test al, al
    jz   .place
    cmp  al, 10
    je   .place
    cmp  cl, FOOTER_RIGHT_COL
    jae  .place
    inc  cl
    jmp  .count

.place:
    mov  al, FOOTER_RIGHT_COL
    cmp  cl, al
    jae  .full
    sub  al, cl
    mov  dl, al
    jmp  .draw

.full:
    mov  dl, 1
    mov  cl, FOOTER_RIGHT_COL

.draw:
    mov  dh, 23
    mov  ch, 1
    mov  bl, 0x2A
    mov  si, status_text
    call print_wrapped_block

    pop  si
    pop  cx
    pop  ax
    ret

draw_modal:
    mov  di, 88
    mov  bx, 64
    mov  cx, 144
    mov  dx, 44
    mov  al, 0x07
    call fill_rect

    mov  di, 90
    mov  bx, 66
    mov  cx, 140
    mov  dx, 40
    mov  al, 0x00
    call fill_rect

    mov  dh, 9
    mov  dl, 12
    mov  bl, 0x0F
    mov  al, [modal_action]
    cmp  al, PROMPT_MKDIR
    jne  .check_file
    mov  si, s_modal_mkdir
    jmp  .title
.check_file:
    cmp  al, PROMPT_MKFILE
    jne  .rename
    mov  si, s_modal_mkfile
    jmp  .title
.rename:
    mov  si, s_modal_rndir
.title:
    call print_string_at

    mov  dh, 11
    mov  dl, 12
    mov  bl, 0x0E
    mov  si, modal_input
    call print_string_at

    mov  dh, 13
    mov  dl, 12
    mov  bl, 0x08
    mov  si, s_modal_help
    call print_string_at
    ret

draw_cursor:
    mov  di, [cursor_x]
    mov  bx, [cursor_y]
    mov  cx, 8
    mov  dx, 2
    mov  al, 0x3F
    call fill_rect

    mov  di, [cursor_x]
    add  di, 3
    mov  bx, [cursor_y]
    sub  bx, 3
    mov  cx, 2
    mov  dx, 8
    mov  al, 0x3F
    call fill_rect
    ret

handle_key:
    mov  ah, [key_scan]
    mov  [last_scan], ah
    mov  [last_char], al

    mov  ah, al
    cmp  ah, 'a'
    jb   .dispatch
    cmp  ah, 'z'
    ja   .dispatch
    sub  ah, 32
    mov  [last_char], ah

.dispatch:
    cmp  byte [setup_step], SETUP_NONE
    jne  handle_kruststart_key

    mov  al, [modal_action]
    cmp  al, PROMPT_NONE
    jne  handle_modal_key

    mov  al, [active_window]
    cmp  al, WINDOW_TERM
    je   handle_terminal_key
    cmp  al, WINDOW_FILES
    je   handle_files_key
    jmp  handle_desktop_key

handle_desktop_key:
    mov  ah, [last_scan]
    cmp  ah, 0x4B
    je   .left
    cmp  ah, 0x4D
    je   .right
    cmp  ah, 0x48
    je   .up
    cmp  ah, 0x50
    je   .down
    mov  al, [last_char]
    cmp  al, 13
    je   .click
    cmp  al, 'T'
    je   .open_term
    cmp  al, 'F'
    je   .open_files
    ret

.left:
    cmp  word [cursor_x], 8
    jbe  .done
    sub  word [cursor_x], 8
    ret
.right:
    cmp  word [cursor_x], 304
    jae  .done
    add  word [cursor_x], 8
    ret
.up:
    cmp  word [cursor_y], 8
    jbe  .done
    sub  word [cursor_y], 8
    ret
.down:
    cmp  word [cursor_y], 172
    jae  .done
    add  word [cursor_y], 8
    ret
.click:
    call desktop_click
    ret
.open_term:
    mov  byte [active_window], WINDOW_TERM
    call set_status_term
    ret
.open_files:
    call go_root
    mov  byte [active_window], WINDOW_FILES
    call refresh_files_view
    ret
.done:
    ret

desktop_click:
    mov  ax, [cursor_x]
    mov  bx, [cursor_y]
    cmp  ax, 16
    jb   .nohit
    cmp  ax, 56
    ja   .check_desktop
    cmp  bx, 40
    jb   .check_files
    cmp  bx, 70
    jbe  .term
.check_files:
    cmp  bx, 92
    jb   .check_desktop
    cmp  bx, 122
    jbe  .files
.check_desktop:
    jmp  .nohit
.term:
    mov  byte [active_window], WINDOW_TERM
    call set_status_term
    ret
.files:
    mov  si, s_cmd_cd_files
    call execute_and_refresh_files
    mov  byte [active_window], WINDOW_FILES
    ret
.nohit:
    ret

handle_terminal_key:
    mov  ah, [last_scan]
    cmp  ah, 0x01
    je   .close
    cmp  ah, 0x2A
    je   .close
    cmp  ah, 0x36
    je   .close
    mov  al, [last_char]
    cmp  al, 13
    je   .enter
    cmp  al, 8
    je   .backspace
    cmp  al, 32
    jb   .hotkeys
    cmp  byte [term_input_len], 40
    jae  .done
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  [term_input + bx], al
    inc  byte [term_input_len]
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  byte [term_input + bx], 0
    ret

.backspace:
    cmp  byte [term_input_len], 0
    je   .done
    dec  byte [term_input_len]
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  byte [term_input + bx], 0
    ret

.enter:
    cmp  byte [term_input_len], 0
    je   .done
    call term_log_append_command
    mov  si, term_input
    call kernel_exec_string
    mov  [term_kind], al
    mov  [term_action], ah
    call copy_low_response_to_temp
    call load_user_name_cache
    cmp  byte [term_action], TERM_ACT_CLEAR
    je   .skip_resp
    call term_log_append_kernel_response
.skip_resp:
    call apply_kernel_action
    call clear_term_input
    ret

.hotkeys:
    mov  al, [last_char]
    cmp  al, 'F'
    jne  .done
    mov  byte [active_window], WINDOW_FILES
    call refresh_files_view
    ret

.close:
    mov  byte [active_window], WINDOW_DESKTOP
    call set_default_status
.done:
    ret

handle_kruststart_key:
    mov  al, [last_char]
    cmp  al, 13
    je   .enter
    cmp  al, 8
    je   .backspace
    cmp  al, 32
    jb   .done

    cmp  byte [setup_step], SETUP_NAME
    je   .name_char

    cmp  byte [term_input_len], 3
    jae  .done
    cmp  al, '+'
    je   .append
    cmp  al, '-'
    je   .append
    cmp  al, '0'
    jb   .done
    cmp  al, '9'
    ja   .done
    jmp  .append

.name_char:
    cmp  byte [term_input_len], 4
    jae  .done
    cmp  al, 'A'
    jb   .done
    cmp  al, 'Z'
    ja   .done

.append:
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  [term_input + bx], al
    inc  byte [term_input_len]
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  byte [term_input + bx], 0
    ret

.backspace:
    cmp  byte [term_input_len], 0
    je   .done
    dec  byte [term_input_len]
    mov  bl, [term_input_len]
    xor  bh, bh
    mov  byte [term_input + bx], 0
    ret

.enter:
    cmp  byte [setup_step], SETUP_NAME
    je   .save_name
    call parse_gmt_input
    jc   .bad_gmt
    mov  [setup_gmt_offset], al
    call finish_kruststart
    ret

.save_name:
    cmp  byte [term_input_len], 0
    je   .bad_name
    mov  si, term_input
    mov  di, setup_name
    call copy_zstr_local
    mov  byte [setup_step], SETUP_GMT
    call clear_term_input
    mov  si, s_ks_gmt
    call set_term_output_from_const
    ret

.bad_name:
    mov  si, s_ks_bad_name
    call set_term_output_from_const
    ret

.bad_gmt:
    mov  si, s_ks_bad_gmt
    call set_term_output_from_const
.done:
    ret

handle_files_key:
    mov  ah, [last_scan]
    cmp  ah, 0x01
    je   .close
    cmp  ah, 0x2A
    je   .close
    cmp  ah, 0x36
    je   .close
    cmp  ah, 0x48
    je   .up
    cmp  ah, 0x50
    je   .down
    cmp  ah, 0x0E
    je   .back
    cmp  ah, 0x53
    je   .delete
    mov  al, [last_char]
    cmp  al, 13
    je   .open
    cmp  al, 'N'
    je   .mkdir
    cmp  al, 'M'
    je   .mkfile
    cmp  al, 'R'
    je   .rename
    cmp  al, 'T'
    je   .term
    cmp  al, 'H'
    je   .home
    ret

.close:
    mov  byte [active_window], WINDOW_DESKTOP
    call set_default_status
    ret
.up:
    cmp  byte [file_sel], 0
    je   .done
    dec  byte [file_sel]
    ret
.down:
    mov  al, [file_item_count]
    cmp  al, 0
    je   .done
    dec  al
    cmp  [file_sel], al
    jae  .done
    inc  byte [file_sel]
    ret
.back:
    mov  si, s_cmd_cd_root
    call execute_and_refresh_files
    ret
.open:
    call file_open_selected
    ret
.delete:
    call file_delete_selected
    ret
.mkdir:
    mov  byte [modal_action], PROMPT_MKDIR
    call clear_modal_input
    call set_status_mkdir
    ret
.mkfile:
    mov  byte [modal_action], PROMPT_MKFILE
    call clear_modal_input
    call set_status_mkfile
    ret
.rename:
    call ensure_selected_dir
    jc   .done
    mov  byte [modal_action], PROMPT_RNDIR
    call clear_modal_input
    call set_status_rename
    ret
.term:
    mov  byte [active_window], WINDOW_TERM
    call set_status_term
    ret
.home:
    mov  si, s_cmd_cd_root
    call execute_and_refresh_files
    ret
.done:
    ret

handle_modal_key:
    mov  al, [last_char]
    cmp  al, 13
    je   .commit
    cmp  al, 8
    je   .backspace
    mov  ah, [last_scan]
    cmp  ah, 0x01
    je   .cancel
    cmp  al, 32
    jb   .done
    cmp  byte [modal_len], 20
    jae  .done
    mov  bl, [modal_len]
    xor  bh, bh
    mov  [modal_input + bx], al
    inc  byte [modal_len]
    mov  bl, [modal_len]
    xor  bh, bh
    mov  byte [modal_input + bx], 0
    ret

.backspace:
    cmp  byte [modal_len], 0
    je   .done
    dec  byte [modal_len]
    mov  bl, [modal_len]
    xor  bh, bh
    mov  byte [modal_input + bx], 0
    ret

.commit:
    call commit_modal
    ret

.cancel:
    mov  byte [modal_action], PROMPT_NONE
    call set_default_status
.done:
    ret

commit_modal:
    mov  al, [modal_len]
    cmp  al, 0
    je   .done

    mov  al, [modal_action]
    cmp  al, PROMPT_MKDIR
    je   .mkdir
    cmp  al, PROMPT_MKFILE
    je   .mkfile
    cmp  al, PROMPT_RNDIR
    je   .rename
    jmp  .done

.mkdir:
    mov  si, s_cmd_mkdir_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, modal_input
    call copy_zstr_local
    mov  si, cmd_buf
    call execute_and_refresh_files
    jmp  .clear

.mkfile:
    mov  si, s_cmd_mkfile_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, modal_input
    call copy_zstr_local
    mov  si, cmd_buf
    call execute_and_refresh_files
    jmp  .clear

.rename:
    call build_selected_name
    mov  si, s_cmd_rndir_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, selected_name
    call copy_zstr_local
    dec  di
    mov  al, ','
    stosb
    mov  si, modal_input
    call copy_zstr_local
    mov  si, cmd_buf
    call execute_and_refresh_files

.clear:
    mov  byte [modal_action], PROMPT_NONE
    call clear_modal_input
.done:
    ret

file_open_selected:
    mov  al, [file_item_count]
    test al, al
    jz   .done
    call build_selected_name
    cmp  byte [selected_is_dir], 1
    jne  .file
    mov  si, s_cmd_cd_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, selected_name
    call copy_zstr_local
    mov  si, cmd_buf
    call execute_and_refresh_files
    ret
.file:
    mov  si, s_status_no_file_app
    call set_status_from_const
.done:
    ret

file_delete_selected:
    mov  al, [file_item_count]
    test al, al
    jz   .done
    call build_selected_name
    mov  si, s_cmd_rm_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, selected_name
    call copy_zstr_local
    mov  si, cmd_buf
    call execute_and_refresh_files
.done:
    ret

ensure_selected_dir:
    call build_selected_name
    cmp  byte [selected_is_dir], 1
    je   .ok
    mov  si, s_status_need_dir
    call set_status_from_const
    stc
    ret
.ok:
    clc
    ret

refresh_files_view:
    mov  si, s_cmd_ls_l
    call kernel_exec_string
    call copy_low_response_to_files
    call parse_file_items
    call load_user_name_cache
    ret

execute_and_refresh_files:
    push si
    call kernel_exec_string
    call copy_low_response_to_status
    call apply_kernel_action
    call refresh_files_view
    pop  si
    ret

go_root:
    mov  si, s_cmd_cd_root
    call kernel_exec_string
    call copy_low_response_to_status
    ret

apply_kernel_action:
    mov  al, [term_action]
    cmp  al, TERM_ACT_CLEAR
    jne  .check_back
    call clear_term_output
.check_back:
    cmp  al, TERM_ACT_BACKCMD
    jne  .check_halt
    mov  byte [active_window], WINDOW_DESKTOP
.check_halt:
    cmp  al, TERM_ACT_HALT
    jne  .done
    cli
.halt:
    hlt
    jmp  .halt
.done:
    ret

parse_file_items:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  byte [file_item_count], 0
    mov  byte [file_sel], 0
    mov  si, files_text

.skip_header:
    lodsb
    test al, al
    jz   .done
    cmp  al, 10
    jne  .skip_header

.line:
    mov  [parse_line_start], si
    mov  al, [si]
    test al, al
    jz   .done
    cmp  al, ' '
    jne  .check_tag
.skip_space:
    inc  si
    mov  al, [si]
    cmp  al, ' '
    je   .skip_space

.check_tag:
    cmp  byte [si], '['
    jne  .next
    mov  dl, [file_item_count]
    cmp  dl, 12
    jae  .next
    xor  bx, bx
    mov  bl, dl
    mov  di, bx
    shl  di, 1
    mov  ax, [parse_line_start]
    mov  [file_item_offsets + di], ax
    mov  al, [si+1]
    cmp  al, 'D'
    jne  .store_file
    mov  byte [file_item_types + bx], 1
    jmp  .stored
.store_file:
    mov  byte [file_item_types + bx], 0
.stored:
    inc  byte [file_item_count]

.next:
    mov  al, [si]
    test al, al
    jz   .done
    cmp  al, 10
    je   .advance
    inc  si
    jmp  .next
.advance:
    inc  si
    jmp  .line

.done:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

build_selected_name:
    push ax
    push bx
    push si
    push di

    xor  bx, bx
    mov  bl, [file_sel]
    shl  bx, 1
    mov  si, [file_item_offsets + bx]
    shr  bx, 1
    mov  al, [file_item_types + bx]
    mov  [selected_is_dir], al

.skip_spaces:
    mov  al, [si]
    cmp  al, ' '
    jne  .skip_tag
    inc  si
    jmp  .skip_spaces

.skip_tag:
    add  si, 7
    mov  di, selected_name
.copy:
    lodsb
    test al, al
    jz   .done_copy
    cmp  al, 10
    je   .done_copy
    stosb
    jmp  .copy
.done_copy:
    mov  byte [di], 0

    pop  di
    pop  si
    pop  bx
    pop  ax
    ret

clear_term_input:
    push ax
    push cx
    push di
    mov  ax, cs
    mov  es, ax
    xor  ax, ax
    mov  di, term_input
    mov  cx, 64
    rep  stosb
    mov  byte [term_input_len], 0
    pop  di
    pop  cx
    pop  ax
    ret

clear_term_output:
    push ax
    push cx
    push di
    mov  ax, cs
    mov  es, ax
    xor  ax, ax
    mov  di, term_output
    mov  cx, 1536
    rep  stosb
    pop  di
    pop  cx
    pop  ax
    ret

clear_modal_input:
    push ax
    push cx
    push di
    mov  ax, cs
    mov  es, ax
    xor  ax, ax
    mov  di, modal_input
    mov  cx, 32
    rep  stosb
    mov  byte [modal_len], 0
    pop  di
    pop  cx
    pop  ax
    ret

copy_low_response_to_temp:
    mov  [term_kind], al
    mov  [term_action], ah
    mov  si, RESP_ADDR
    mov  di, resp_copy
    call copy_low_zstr_to_local
    ret

copy_low_response_to_files:
    mov  si, RESP_ADDR
    mov  di, files_text
    call copy_low_zstr_to_local
    mov  si, RESP_ADDR
    mov  di, status_text
    call copy_low_zstr_to_local
    ret

copy_low_response_to_status:
    mov  [term_kind], al
    mov  [term_action], ah
    mov  si, RESP_ADDR
    mov  di, status_text
    call copy_low_zstr_to_local
    ret

copy_low_zstr_to_local:
    push ax
    push ds
    push es

    xor  ax, ax
    mov  ds, ax
    mov  ax, cs
    mov  es, ax
.loop:
    lodsb
    stosb
    test al, al
    jnz  .loop

    pop  es
    pop  ds
    pop  ax
    ret

copy_zstr_local:
    push ax
    push es
    mov  ax, cs
    mov  es, ax
.loop:
    lodsb
    stosb
    test al, al
    jnz  .loop
    pop  es
    pop  ax
    ret

fill_rect:
    mov  [rect_x], di
    mov  [rect_y], bx
    mov  [rect_w], cx
    mov  [rect_h], dx
    mov  [rect_color], al

    push ax
    push bx
    push cx
    push dx
    push di
    push es
    push bp

    mov  ax, 0xA000
    mov  es, ax
    mov  bx, [rect_y]
    mov  bp, [rect_h]

.row:
    mov  di, bx
    shl  di, 6
    mov  dx, bx
    shl  dx, 8
    add  di, dx
    add  di, [rect_x]
    mov  cx, [rect_w]
    mov  al, [rect_color]
    rep  stosb
    inc  bx
    dec  bp
    jnz  .row

    pop  bp
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

print_string_at:
    push ax
    push bx
    push cx
    push dx

    mov  [text_row], dh
    mov  [text_col], dl
    mov  [text_start_col], dl
    mov  [text_color], bl
    call set_text_cursor

.loop:
    lodsb
    test al, al
    jz   .done
    cmp  al, 13
    je   .loop
    cmp  al, 10
    je   .newline
    cmp  al, 32
    jb   .loop
    call draw_text_char
    inc  byte [text_col]
    jmp  .loop

.newline:
    inc  byte [text_row]
    mov  al, [text_start_col]
    mov  [text_col], al
    call set_text_cursor
    jmp  .loop

.done:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

print_line_at:
    push ax
    push bx
    push dx
    push si

    mov  [text_row], dh
    mov  [text_col], dl
    mov  [text_start_col], dl
    mov  [text_color], bl
    call set_text_cursor

.loop:
    lodsb
    test al, al
    jz   .done
    cmp  al, 13
    je   .loop
    cmp  al, 10
    je   .done
    cmp  al, 32
    jb   .loop
    call draw_text_char
    inc  byte [text_col]
    jmp  .loop

.done:
    pop  si
    pop  dx
    pop  bx
    pop  ax
    ret

print_wrapped_block:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  [text_row], dh
    mov  [text_col], dl
    mov  [text_start_col], dl
    mov  [text_color], bl
    mov  [wrap_width], cl
    mov  al, dh
    add  al, ch
    dec  al
    mov  [wrap_last_row], al

.loop:
    lodsb
    test al, al
    jz   .done
    cmp  al, 13
    je   .loop
    cmp  al, 10
    je   .newline
    cmp  al, 32
    jb   .loop
    cmp  al, 126
    ja   .loop

    mov  ah, [text_col]
    sub  ah, [text_start_col]
    cmp  ah, [wrap_width]
    jb   .print
    push ax
    call wrapped_advance_line
    pop  ax
    jc   .done
    cmp  al, ' '
    je   .loop

.print:
    call draw_text_char
    inc  byte [text_col]
    jmp  .loop

.newline:
    call wrapped_advance_line
    jc   .done
    jmp  .loop

.done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

wrapped_advance_line:
    mov  al, [text_row]
    cmp  al, [wrap_last_row]
    jae  .full
    inc  byte [text_row]
    mov  al, [text_start_col]
    mov  [text_col], al
    call set_text_cursor
    clc
    ret
.full:
    stc
    ret

set_text_cursor:
    ret

set_text_metrics_default:
    mov  byte [text_cell_h], TEXT_CELL_H
    mov  byte [text_cell_w], TEXT_DEFAULT_CELL_W
    mov  byte [text_glyph_w], TEXT_DEFAULT_GLYPH_W
    mov  byte [text_glyph_h], TEXT_DEFAULT_GLYPH_H
    mov  byte [text_compact], 0
    ret

set_text_metrics_term:
    mov  byte [text_cell_h], TEXT_CELL_H
    mov  byte [text_cell_w], TEXT_TERM_CELL_W
    mov  byte [text_glyph_w], TEXT_TERM_GLYPH_W
    mov  byte [text_glyph_h], TEXT_TERM_GLYPH_H
    mov  byte [text_compact], 0
    ret

set_text_metrics_terminal:
    mov  byte [text_cell_h], TEXT_TERMINAL_CELL_H
    mov  byte [text_cell_w], TEXT_TERMINAL_CELL_W
    mov  byte [text_glyph_w], TEXT_TERMINAL_GLYPH_W
    mov  byte [text_glyph_h], TEXT_TERMINAL_GLYPH_H
    mov  byte [text_compact], 0
    ret

draw_term_input_block:
    push ax
    push bx
    push cx
    push dx
    push si

    mov  si, term_input
    mov  dh, TERM_PROMPT_ROW
    mov  dl, TERM_TEXT_COL
    add  dl, [user_prompt_len]
    inc  dl
    mov  bl, 0x0F
    mov  cx, 0x0218
    call print_wrapped_block

    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

start_kruststart_if_needed:
    call settings_magic_present
    jnc  .done

    mov  byte [setup_step], SETUP_NAME
    mov  byte [active_window], WINDOW_TERM
    call clear_term_input

    mov  si, s_ks_prompt
    mov  di, user_name_cache
    call copy_zstr_local
    mov  byte [user_prompt_len], 6

    mov  si, s_ks_name
    call set_term_output_from_const
    mov  si, s_status_kruststart
    call set_status_from_const
    mov  byte [render_pending], 1

.done:
    ret

set_term_output_from_const:
    push di
    call clear_term_output
    mov  di, term_output
    call copy_zstr_local
    pop  di
    ret

parse_gmt_input:
    push bx
    push cx
    push dx
    push si

    mov  si, term_input
    xor  bx, bx
    xor  cx, cx

    mov  al, [si]
    cmp  al, '-'
    jne  .check_plus
    mov  bl, 1
    inc  si
    jmp  .digits

.check_plus:
    cmp  al, '+'
    jne  .digits
    inc  si

.digits:
    cmp  byte [si], 0
    je   .error

.loop:
    lodsb
    test al, al
    jz   .range
    cmp  al, '0'
    jb   .error
    cmp  al, '9'
    ja   .error
    sub  al, '0'
    mov  dl, cl
    shl  cl, 1
    shl  dl, 3
    add  cl, dl
    add  cl, al
    jmp  .loop

.range:
    cmp  bl, 0
    jne  .negative
    cmp  cl, 14
    ja   .error
    mov  al, cl
    clc
    jmp  .done

.negative:
    cmp  cl, 12
    ja   .error
    mov  al, cl
    neg  al
    clc
    jmp  .done

.error:
    stc

.done:
    pop  si
    pop  dx
    pop  cx
    pop  bx
    ret

finish_kruststart:
    mov  si, s_cmd_renamepc_prefix
    mov  di, cmd_buf
    call copy_zstr_local
    dec  di
    mov  si, setup_name
    call copy_zstr_local
    mov  si, cmd_buf
    call kernel_exec_string
    call copy_low_response_to_status
    call store_kruststart_settings

    mov  byte [setup_step], SETUP_NONE
    call clear_term_input
    call load_user_name_cache
    mov  si, s_ks_done
    call set_term_output_from_const
    call set_status_term
    ret

settings_magic_present:
    push ax
    push es

    xor  ax, ax
    mov  es, ax
    cmp  byte [es:SETTINGS_MAGIC_ADDR], 'K'
    jne  .missing
    cmp  byte [es:SETTINGS_MAGIC_ADDR + 1], 'S'
    jne  .missing
    cmp  byte [es:SETTINGS_MAGIC_ADDR + 2], 'T'
    jne  .missing
    cmp  byte [es:SETTINGS_MAGIC_ADDR + 3], '1'
    jne  .missing
    clc
    jmp  .done

.missing:
    stc

.done:
    pop  es
    pop  ax
    ret

load_settings_cache:
    push ax
    push es

    mov  byte [gmt_offset], 0
    call settings_magic_present
    jc   .done
    xor  ax, ax
    mov  es, ax
    mov  al, [es:SETTINGS_GMT_ADDR]
    mov  [gmt_offset], al

.done:
    pop  es
    pop  ax
    ret

store_kruststart_settings:
    push ax
    push es

    xor  ax, ax
    mov  es, ax
    mov  byte [es:SETTINGS_MAGIC_ADDR], 'K'
    mov  byte [es:SETTINGS_MAGIC_ADDR + 1], 'S'
    mov  byte [es:SETTINGS_MAGIC_ADDR + 2], 'T'
    mov  byte [es:SETTINGS_MAGIC_ADDR + 3], '1'
    mov  al, [setup_gmt_offset]
    mov  [es:SETTINGS_GMT_ADDR], al
    mov  [gmt_offset], al
    call save_settings_sector

    pop  es
    pop  ax
    ret

save_settings_sector:
    push ax
    push bx
    push cx
    push dx
    push ds

    xor  ax, ax
    mov  ds, ax
    mov  ah, 0x03
    mov  al, 1
    mov  ch, 0
    mov  cl, NAME_SECTOR
    mov  dh, 0
    mov  dl, [BOOT_DRIVE_ADDR]
    mov  bx, NAME_ADDR
    int  0x13

    pop  ds
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

poll_clock_tick:
    push ax
    push cx
    push dx

    mov  ah, 0x02
    int  0x1A
    jc   .done
    mov  al, cl
    call bcd_to_bin
    cmp  al, [clock_last_min]
    je   .done
    mov  [clock_last_min], al
    mov  byte [render_pending], 1

.done:
    pop  dx
    pop  cx
    pop  ax
    ret

update_clock_text:
    push ax
    push bx
    push cx
    push dx
    push di

    call load_settings_cache

    mov  ah, 0x02
    int  0x1A
    jc   .build

    mov  al, ch
    call bcd_to_bin
    xor  ah, ah
    mov  bl, [gmt_offset]
    xor  bh, bh
    test bl, 0x80
    jz   .offset_ready
    mov  bh, 0xFF

.offset_ready:
    add  ax, bx
    cmp  ax, 0
    jge  .check_high
    add  ax, 24

.check_high:
    cmp  ax, 24
    jl   .store_hour
    sub  ax, 24

.store_hour:
    mov  [clock_hour], al
    mov  al, cl
    call bcd_to_bin
    mov  [clock_minute], al

.build:
    mov  al, [clock_hour]
    mov  di, clock_text
    call write_two_digits
    mov  byte [clock_text + 2], ':'
    mov  al, [clock_minute]
    mov  di, clock_text + 3
    call write_two_digits
    mov  byte [clock_text + 5], 0
    call build_gmt_text

    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

bcd_to_bin:
    push bx
    mov  bl, al
    and  al, 0x0F
    mov  bh, al
    mov  al, bl
    shr  al, 4
    mov  bl, 10
    mul  bl
    add  al, bh
    pop  bx
    ret

write_two_digits:
    push ax
    push bx
    xor  ah, ah
    mov  bl, 10
    div  bl
    add  al, '0'
    mov  [di], al
    mov  al, ah
    add  al, '0'
    mov  [di + 1], al
    pop  bx
    pop  ax
    ret

build_gmt_text:
    mov  byte [gmt_text], 'G'
    mov  byte [gmt_text + 1], 'M'
    mov  byte [gmt_text + 2], 'T'
    mov  al, [gmt_offset]
    test al, 0x80
    jz   .positive
    mov  byte [gmt_text + 3], '-'
    neg  al
    jmp  .digits

.positive:
    mov  byte [gmt_text + 3], '+'

.digits:
    mov  di, gmt_text + 4
    call write_two_digits
    mov  byte [gmt_text + 6], 0
    ret

draw_text_char:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es

    cmp  al, ' '
    je   .done

    xor  bx, bx
    mov  bl, al
    shl  bx, 3
    mov  ax, [font_seg]
    mov  es, ax
    mov  si, [font_off]
    add  si, bx

    xor  ax, ax
    mov  al, [text_col]
    mov  bl, [text_cell_w]
    mul  bl
    inc  ax
    mov  di, ax

    xor  ax, ax
    mov  al, [text_row]
    mov  dl, [text_cell_h]
    mul  dl
    add  ax, 1
    mov  bx, ax

    xor  dx, dx
    mov  dl, [text_glyph_h]
    mov  bp, dx
.row:
    push si
    push di
    push bx
    push es

    mov  ax, [font_seg]
    mov  es, ax
    mov  dl, [es:si]

    pop  es

    xor  cx, cx
    mov  cl, [text_glyph_w]
    cmp  byte [text_compact], 0
    jne  .compact_cols
    mov  ah, 0x80

.col:
    test dl, ah
    jz   .skip

    mov  al, [text_color]
    call put_pixel

.skip:
    inc  di
    shr  ah, 1
    loop .col
    jmp  .row_done

.compact_cols:
    push si
    mov  si, compact_masks

.compact_col:
    mov  ah, [si]
    test dl, ah
    jz   .compact_skip

    mov  al, [text_color]
    call put_pixel

.compact_skip:
    inc  si
    inc  di
    loop .compact_col
    pop  si

.row_done:
    pop  bx
    pop  di
    pop  si

    inc  si
    inc  bx
    dec  bp
    jnz  .row
.done:
    pop  es
    pop  bp
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

put_pixel:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    mov  cl, al
    mov  ax, 0xA000
    mov  es, ax
    mov  ax, bx
    shl  ax, 6
    mov  dx, bx
    shl  dx, 8
    add  ax, dx
    add  ax, di
    mov  di, ax
    mov  [es:di], cl

    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

kernel_init_state:
    mov  ah, KAPI_FN_INIT
    int  0x60
    ret

kernel_exec_string:
    mov  ah, KAPI_FN_EXEC
    int  0x60
    ret

init_mouse_support:
    push ax
    push bx
    push cx
    push dx
    push ds

    xor  ax, ax
    mov  ds, ax
    mov  ax, [0x00CC]
    or   ax, [0x00CE]
    jz   .none

    mov  ax, 0x0000
    int  0x33
    test ax, ax
    jz   .none

    mov  ax, 0x0007
    xor  cx, cx
    mov  dx, 319
    int  0x33

    mov  ax, 0x0008
    xor  cx, cx
    mov  dx, 199
    int  0x33

    mov  byte [mouse_available], 1
    jmp  .done

.none:
    mov  byte [mouse_available], 0

.done:
    pop  ds
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

poll_mouse:
    cmp  byte [mouse_available], 0
    je   .done

    push ax
    push bx
    push cx
    push dx

    mov  ax, 0x0003
    int  0x33
    shr  cx, 1
    cmp  cx, [cursor_x]
    jne  .moved
    cmp  dx, [cursor_y]
    jne  .moved
    jmp  .store_pos
.moved:
    mov  byte [render_pending], 1
.store_pos:
    mov  [cursor_x], cx
    mov  [cursor_y], dx

    test bx, 1
    jz   .released
    cmp  byte [mouse_prev_left], 0
    jne  .store
    call handle_mouse_click
    mov  byte [render_pending], 1
    mov  byte [mouse_prev_left], 1
    jmp  .store

.released:
    mov  byte [mouse_prev_left], 0

.store:
    pop  dx
    pop  cx
    pop  bx
    pop  ax
.done:
    ret

poll_shift_exit:
    push ax
    push si
    push di

    cmp  byte [setup_step], SETUP_NONE
    jne  .done

    mov  ah, 0x02
    int  0x16
    test al, 0x03
    jz   .released

    cmp  byte [shift_exit_down], 0
    jne  .done
    mov  byte [shift_exit_down], 1

    cmp  byte [active_window], WINDOW_DESKTOP
    je   .done

    mov  byte [modal_action], PROMPT_NONE
    mov  byte [active_window], WINDOW_DESKTOP
    call set_default_status
    mov  byte [render_pending], 1
    jmp  .done

.released:
    mov  byte [shift_exit_down], 0

.done:
    pop  di
    pop  si
    pop  ax
    ret

handle_mouse_click:
    cmp  byte [modal_action], PROMPT_NONE
    jne  .done
    mov  al, [active_window]
    cmp  al, WINDOW_DESKTOP
    je   .desktop
    cmp  al, WINDOW_FILES
    je   .files
    jmp  .done
.desktop:
    call desktop_click
    ret
.files:
    call files_mouse_click
.done:
    ret

files_mouse_click:
    push ax
    push bx
    push cx

    mov  ax, [cursor_x]
    mov  bx, [cursor_y]
    cmp  ax, 78
    jb   .done
    cmp  ax, 298
    ja   .done
    cmp  bx, 48
    jb   .done
    cmp  bx, 143
    ja   .done

    sub  bx, 48
    mov  cl, 3
    shr  bx, cl
    mov  al, [file_item_count]
    xor  ah, ah
    cmp  bx, ax
    jae  .done
    cmp  bl, [file_sel]
    jne  .select
    call file_open_selected
    jmp  .done
.select:
    mov  [file_sel], bl

.done:
    pop  cx
    pop  bx
    pop  ax
    ret

load_user_name_cache:
    push ax
    push cx
    push si
    push di

    mov  byte [user_name_cache], '/'
    mov  si, DIR_ADDR
    mov  di, user_name_cache + 1
    call copy_low_zstr_to_local
    cmp  byte [user_name_cache + 1], 0
    jne  .count

    mov  si, NAME_ADDR
    mov  di, user_name_cache
    call copy_low_zstr_to_local
    cmp  byte [user_name_cache], 0
    jne  .count
    mov  si, s_fallback_user
    mov  di, user_name_cache
    call copy_zstr_local

.count:
    mov  si, user_name_cache
    xor  cx, cx
.loop:
    mov  al, [si]
    test al, al
    jz   .done
    inc  cl
    inc  si
    jmp  .loop
.done:
    mov  [user_prompt_len], cl

    pop  di
    pop  si
    pop  cx
    pop  ax
    ret

term_log_append_command:
    call term_log_get_tail
    mov  si, user_name_cache
    call term_log_append_local_string_at_di
    mov  al, '>'
    call term_log_append_char_at_di
    mov  si, term_input
    call term_log_append_local_string_at_di
    mov  al, 10
    call term_log_append_char_at_di
    ret

term_log_append_kernel_response:
    cmp  byte [resp_copy], 0
    je   .done
    call term_log_get_tail
    mov  si, s_kernel_prompt
    call term_log_append_local_string_at_di
    mov  si, resp_copy
    call term_log_append_local_string_at_di
    mov  al, 10
    call term_log_append_char_at_di
.done:
    ret

term_log_get_tail:
    mov  di, term_output
.loop:
    cmp  byte [di], 0
    je   .done
    inc  di
    jmp  .loop
.done:
    ret

term_log_append_local_string_at_di:
    push ax
.loop:
    lodsb
    test al, al
    jz   .done
    stosb
    jmp  .loop
.done:
    mov  byte [di], 0
    pop  ax
    ret

term_log_append_char_at_di:
    stosb
    mov  byte [di], 0
    ret

kbd_read:
    mov  ah, 0x01
    int  0x16
    jz   .none
    mov  ah, 0x10
    int  0x16
    mov  [key_scan], ah
    cmp  al, 0xE0
    jne  .done
    xor  al, al
.done:
    ret
.none:
    xor  ax, ax
    mov  [key_scan], ah
    ret

set_default_status:
    mov  si, s_status_default
    jmp  set_status_from_const

set_status_term:
    mov  si, s_status_term
    jmp  set_status_from_const

set_status_mkdir:
    mov  si, s_status_mkdir
    jmp  set_status_from_const

set_status_mkfile:
    mov  si, s_status_mkfile
    jmp  set_status_from_const

set_status_rename:
    mov  si, s_status_rndir

set_status_from_const:
    mov  di, status_text
    call copy_zstr_local
    ret

font_off dw 0
font_seg dw 0
loading_highlight db 0
loading_index db 0
loading_dot_x dw 148, 162, 172, 176, 172, 162, 148, 142
loading_dot_y dw 84, 78, 84, 96, 108, 114, 108, 96

runtime_state_begin:
rect_x dw 0
rect_y dw 0
rect_w dw 0
rect_h dw 0
rect_color db 0

text_row db 0
text_col db 0
text_start_col db 0
text_color db 0
text_cell_h db 0
text_cell_w db 0
text_glyph_w db 0
text_glyph_h db 0
text_compact db 0
wrap_width db 0
wrap_last_row db 0

cursor_x dw 0
cursor_y dw 0
active_window db 0
modal_action db 0
modal_len db 0
term_input_len db 0
term_kind db 0
term_action db 0
file_item_count db 0
file_sel db 0
selected_is_dir db 0
key_scan db 0
last_scan db 0
last_char db 0
mouse_available db 0
mouse_prev_left db 0
shift_exit_down db 0
user_prompt_len db 0
render_pending db 0
setup_step db 0
setup_gmt_offset db 0
gmt_offset db 0
clock_hour db 0
clock_minute db 0
clock_last_min db 0

term_input  times 64 db 0
term_output times 1536 db 0
resp_copy   times 1536 db 0
files_text  times 1536 db 0
status_text times 96 db 0
modal_input times 32 db 0
selected_name times 32 db 0
user_name_cache times 16 db 0
setup_name times 5 db 0
clock_text db '00:00',0
gmt_text db 'GMT+00',0
cmd_buf     times 96 db 0
file_item_offsets times 12 dw 0
file_item_types   times 12 db 0
parse_line_start dw 0
runtime_state_end:

compact_masks db 0x80, 0x40, 0x20, 0x10, 0x08, 0x04

s_loading_title db 'loading krustOS...',0
s_loading_hint db 'preparing desktop and kernel services',0
s_title db 'KrustOS',0
s_subtitle db 'kernel driven',0
s_clock_title db 'Time',0
s_icon_term db 'Terminal',0
s_icon_files db 'Files',0
s_term_title db 'Kernel Terminal',0
s_term_help db 'ESC close / F files',0
s_files_title db 'File Manager',0
s_files_help db 'UP/DN open DEL rm N dir M file',0
s_modal_mkdir db 'New folder name',0
s_modal_mkfile db 'New file name.ext',0
s_modal_rndir db 'Rename selected dir',0
s_modal_help db 'ENTER save  ESC cancel',0
s_user_prompt_suffix db '>',0
s_kernel_prompt db 'kernel> ',0
s_fallback_user db 'USER',0
s_status_default db 'Mouse or arrows.',0
s_status_term db 'Terminal ready.',0
s_status_mkdir db 'Create folder: type name and press Enter.',0
s_status_mkfile db 'Create file: type NAME.EXT and press Enter.',0
s_status_rndir db 'Rename folder: type new name and press Enter.',0
s_status_no_file_app db 'No visual app is assigned to this file yet.',0
s_status_need_dir db 'Select a directory to rename.',0
s_status_kruststart db 'KrustStart setup.',0
s_ks_prompt db 'KStart',0
s_ks_name db 'KrustStart',10,'How do you want to call you?',10,'Only 4 letters.',0
s_ks_gmt db 'What is your GMT?',10,'Example: +2 or -5',0
s_ks_bad_name db 'Name is required.',10,'Use A-Z, max 4 letters.',0
s_ks_bad_gmt db 'Bad GMT.',10,'Use -12 to +14.',0
s_ks_done db 'KrustStart complete.',10,'Settings saved.',0

s_cmd_ls_l db 'LS-L',0
s_cmd_cd_root db 'CD',0
s_cmd_cd_prefix db 'CD ',0
s_cmd_cd_files db 'CD FILES',0
s_cmd_mkdir_prefix db 'MKDIR ',0
s_cmd_mkfile_prefix db 'MKFILE ',0
s_cmd_rm_prefix db 'RM ',0
s_cmd_rndir_prefix db 'RNDIR ',0
s_cmd_renamepc_prefix db 'RENAMEPC ',0
