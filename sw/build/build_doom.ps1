# ============================================================================
# File: build_doom.ps1
# Description: Compiles Bare-Metal DOOM for RV64IM ZedBoard SoC
# Target: DDR3 Memory @ 0x8010_0000
# ============================================================================

$DEFAULT_GCC_BIN = "C:\opt\riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-w64-mingw32\bin"
if ($env:RISCV_TOOLCHAIN) {
    $GCC_BIN = $env:RISCV_TOOLCHAIN
} elseif (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $GCC_BIN = Split-Path (Get-Command riscv64-unknown-elf-gcc).Source
} else {
    $GCC_BIN = $DEFAULT_GCC_BIN
}

$CC = Join-Path $GCC_BIN "riscv64-unknown-elf-gcc.exe"
$OBJCOPY = Join-Path $GCC_BIN "riscv64-unknown-elf-objcopy.exe"
$OBJDUMP = Join-Path $GCC_BIN "riscv64-unknown-elf-objdump.exe"
$SIZE = Join-Path $GCC_BIN "riscv64-unknown-elf-size.exe"

$REPO_ROOT = "$PSScriptRoot/../.."
Set-Location $REPO_ROOT

$FLAGS = @(
    "-march=rv64im",
    "-mabi=lp64",
    "-mcmodel=medany",
    "-O2",
    "-ffreestanding",
    "-fno-builtin",
    "-nostdlib",
    "-nostartfiles",
    "-Wall",
    "-Wno-unused-variable",
    "-Wno-unused-function",
    "-Wno-pointer-to-int-cast",
    "-Wno-int-to-pointer-cast",
    "-Wno-format",
    "-DCMAP256",
    "-DDOOMGENERIC_RESX=320",
    "-DDOOMGENERIC_RESY=200",
    "-DNORMALUNIX",
    "-DDEBUG_MILESTONES",
    "-Isw/include",
    "-Isw/common",
    "-Isw/doom/doomgeneric",
    "-T", "sw/linker/linker_ddr.ld"
)

Write-Host "=================================================================="
Write-Host "  Compiling Bare-Metal DOOM for RV64IM DDR3 @ 0x80100000          "
Write-Host "=================================================================="

# Gather all DoomGeneric engine C sources
$DOOM_SRCS = Get-ChildItem sw/doom/doomgeneric/*.c | Where-Object {
    $_.Name -notmatch "doomgeneric_(win|sdl|xlib|allegro|emscripten|linuxvt|soso|sosox)\.c" -and
    $_.Name -notmatch "w_file_stdc\.c" -and
    $_.Name -notmatch "w_file_mem\.c" -and
    $_.Name -notmatch "doomgeneric_rv64\.c" -and
    $_.Name -notmatch "i_sdl" -and
    $_.Name -notmatch "i_allegro" -and
    $_.Name -notmatch "mus2mid" -and
    $_.Name -notmatch "gusconf"
} | ForEach-Object { $_.FullName }

# Add SoC hardware drivers, minimal libc, platform glue & main
$SOC_SRCS = @(
    "sw/linker/crt0.S",
    "sw/common/libc.c",
    "sw/doom/platform/doom_main.c",
    "sw/drivers/timer.c",
    "sw/drivers/gpio.c",
    "sw/drivers/vga.c",
    "sw/drivers/vga_text.c",
    "sw/drivers/uart.c",
    "sw/doom/platform/doomgeneric_rv64.c",
    "sw/doom/platform/w_file_mem.c"
)

$ALL_SRCS = $SOC_SRCS + $DOOM_SRCS

Write-Host "Compiling $( $ALL_SRCS.Count ) source files..."

& $CC @FLAGS -o sw/build/doom_rv64.elf @ALL_SRCS

if ($LASTEXITCODE -ne 0) {
    Write-Error "DOOM compilation failed!"
    exit 1
}

Write-Host "[1/3] Compiled sw/build/doom_rv64.elf"
& $OBJCOPY -O binary sw/build/doom_rv64.elf sw/build/doom_rv64.bin
Write-Host "[2/3] Generated raw binary sw/build/doom_rv64.bin"
& $OBJDUMP -d sw/build/doom_rv64.elf > sw/build/doom_rv64.dis
Write-Host "[3/3] Generated disassembly sw/build/doom_rv64.dis"

& $SIZE sw/build/doom_rv64.elf
$bin_size = (Get-Item sw/build/doom_rv64.bin).Length
Write-Host "=================================================================="
Write-Host "  BUILD COMPLETE! Raw Binary Size: $bin_size bytes               "
Write-Host "  Destination: DDR3 @ 0x80100000 (Load via JTAG scripts)          "
Write-Host "=================================================================="
