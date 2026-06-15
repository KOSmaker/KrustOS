@echo off
setlocal

cd /d "%~dp0"
set "SCRIPT_DIR=%~dp0"

set "NASM=C:\Users\"YOUR USER"\Desktop\nasm-3.01\nasm.exe"
set "QEMU_IMG=C:\Program Files\qemu\qemu-img.exe"
set "QEMU_SYS=C:\Program Files\qemu\qemu-system-x86_64.exe"

set "BOOT_BIN=%SCRIPT_DIR%boot.bin"
set "KERNEL_BIN=%SCRIPT_DIR%kernel.bin"
set "VISUAL_BIN=%SCRIPT_DIR%KrustOSvisual.bin"
set "BASE_IMG=%SCRIPT_DIR%base.img"



set "IMG_SIG=KRUSTIMG1"
set "IMG_SIG_OFFSET=28672"
set "BASE_IMG_BYTES=2147483648"
set "BASE_CREATED=0"

echo Stopping QEMU if it is running...
taskkill /F /IM qemu-system-x86_64.exe 2>nul
timeout /t 1 /nobreak >nul

:: Check NASM
if not exist "%NASM%" (
    echo ERROR: NASM not found at:
    echo %NASM%
    pause
    exit /b 1
)

echo Building binaries...

"%NASM%" -f bin "%SCRIPT_DIR%boot.asm" -o "%BOOT_BIN%"
if errorlevel 1 (
    echo ERROR: boot.asm failed
    pause
    exit /b 1
)

"%NASM%" -f bin "%SCRIPT_DIR%kernel.asm" -o "%KERNEL_BIN%"
if errorlevel 1 (
    echo ERROR: kernel.asm failed
    pause
    exit /b 1
)

"%NASM%" -f bin "%SCRIPT_DIR%KrustOSvisual.asm" -o "%VISUAL_BIN%"
if errorlevel 1 (
    echo ERROR: KrustOSvisual.asm failed
    pause
    exit /b 1
)

echo All files compiled OK!

:: Create base.img if missing
if not exist "%BASE_IMG%" (
    if exist "%QEMU_IMG%" (
        echo Creating base.img via qemu-img...
        "%QEMU_IMG%" create -f raw "%BASE_IMG%" 2G
        if errorlevel 1 (
            echo ERROR: qemu-img failed to create base.img
            pause
            exit /b 1
        )
        echo base.img created (2G)
    ) else (
        echo qemu-img.exe not found, creating base.img via PowerShell...
        powershell -NoProfile -Command ^
            "$f = [System.IO.File]::Open($env:BASE_IMG, 'Create', 'Write', 'None');" ^
            "$f.SetLength([int64]$env:BASE_IMG_BYTES);" ^
            "$f.Close();"
        if errorlevel 1 (
            echo ERROR: PowerShell failed to create base.img
            pause
            exit /b 1
        )
        echo base.img created (2G)
    )
    set "BASE_CREATED=1"
)


if not exist "%BASE_IMG%" (
    echo ERROR: base.img is still missing:
    echo %BASE_IMG%
    pause
    exit /b 1
)

echo Ensuring 2G base.img size...
powershell -NoProfile -Command ^
    "$f = [System.IO.File]::Open($env:BASE_IMG, 'Open', 'ReadWrite', 'ReadWrite');" ^
    "if ($f.Length -ne [int64]$env:BASE_IMG_BYTES) { $f.SetLength([int64]$env:BASE_IMG_BYTES) }" ^
    "$f.Close();"
if errorlevel 1 (
    echo ERROR: failed to resize base.img
    pause
    exit /b 1
)

:: Validate signature if base.img already existed
if "%BASE_CREATED%"=="0" (
    echo Validating existing base.img signature...

    powershell -NoProfile -Command ^
        "$sig = [System.Text.Encoding]::ASCII.GetBytes($env:IMG_SIG);" ^
        "$offset = [int64]$env:IMG_SIG_OFFSET;" ^
        "$item = Get-Item -LiteralPath $env:BASE_IMG;" ^
        "if ($item.Length -lt ($offset + $sig.Length)) { exit 10 }" ^
        "$f = [System.IO.File]::Open($env:BASE_IMG, 'Open', 'Read', 'ReadWrite');" ^
        "$buf = New-Object byte[] $sig.Length;" ^
        "$f.Seek($offset, 0) | Out-Null;" ^
        "$read = $f.Read($buf, 0, $buf.Length);" ^
        "$f.Close();" ^
        "if ($read -ne $sig.Length) { exit 11 }" ^
        "for ($i = 0; $i -lt $sig.Length; $i++) { if ($buf[$i] -ne $sig[$i]) { exit 12 } }"

    if errorlevel 1 (
        echo Existing base.img is unsigned. Checking for a legacy Krust image...

        powershell -NoProfile -Command ^
            "$item = Get-Item -LiteralPath $env:BASE_IMG;" ^
            "if ($item.Length -lt 512) { exit 20 }" ^
            "$f = [System.IO.File]::Open($env:BASE_IMG, 'Open', 'Read', 'ReadWrite');" ^
            "$f.Seek(510, 0) | Out-Null;" ^
            "$buf = New-Object byte[] 2;" ^
            "$read = $f.Read($buf, 0, 2);" ^
            "$f.Close();" ^
            "if ($read -ne 2) { exit 21 }" ^
            "if ($buf[0] -ne 0x55 -or $buf[1] -ne 0xAA) { exit 22 }"

        if errorlevel 1 (
            echo ERROR: base.img has no valid Krust signature.
            echo Delete base.img and run this script again.
            pause
            exit /b 1
        )

        echo Legacy Krust image detected. Upgrading signature...
    ) else (
        echo base.img signature OK.
    )
)

echo Writing boot/kernel/KrustOSvisual into base.img...

set "P_BASE=%BASE_IMG%"
set "P_BOOT=%BOOT_BIN%"
set "P_KERN=%KERNEL_BIN%"
set "P_VISUAL=%VISUAL_BIN%"

powershell -NoProfile -Command ^
    "$f = [System.IO.File]::Open('%P_BASE%', 'Open', 'ReadWrite', 'None');" ^
    "$boot = [System.IO.File]::ReadAllBytes('%P_BOOT%');" ^
    "$kern = [System.IO.File]::ReadAllBytes('%P_KERN%');" ^
    "$visual = [System.IO.File]::ReadAllBytes('%P_VISUAL%');" ^
    "$sig = [System.Text.Encoding]::ASCII.GetBytes('%IMG_SIG%');" ^
    "$f.Seek(0, 0) | Out-Null; $f.Write($boot, 0, $boot.Length);" ^
    "$f.Seek(512, 0) | Out-Null; $f.Write($kern, 0, $kern.Length);" ^
    "$f.Seek(8704, 0) | Out-Null; $f.Write($visual, 0, $visual.Length);" ^
    "$f.Seek(%IMG_SIG_OFFSET%, 0) | Out-Null; $f.Write($sig, 0, $sig.Length);" ^
    "$f.Close();"

if errorlevel 1 (
    echo ERROR: failed to update base.img
    pause
    exit /b 1
)

if not exist "%QEMU_SYS%" (
    echo ERROR: QEMU not found at:
    echo %QEMU_SYS%
    echo.
    echo Update QEMU_SYS in run.bat or install QEMU there.
    pause
    exit /b 1
)

echo Starting QEMU...
"%QEMU_SYS%" -drive file="%BASE_IMG%",format=raw,if=ide,index=0

pause
