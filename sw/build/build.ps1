# ============================================================================
# File: build.ps1
# Description: Compiles On-Chip BRAM Diagnostic Bootloader for RV64IM
# Target: 0x0000_0000 (8 KB On-Chip Boot BRAM)
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
    "-O2",
    "-ffreestanding",
    "-nostdlib",
    "-nostartfiles",
    "-Wall",
    "-Isw/include",
    "-T", "sw/linker/linker.ld"
)

Write-Host "=================================================================="
Write-Host "  Compiling RV64IM BRAM Diagnostic Bootloader                     "
Write-Host "=================================================================="

$SOURCES = @(
    "sw/linker/crt0.S",
    "sw/bootloader/main.c",
    "sw/drivers/uart.c",
    "sw/drivers/timer.c",
    "sw/drivers/gpio.c",
    "sw/drivers/vga.c",
    "sw/drivers/vga_text.c"
)

& $CC @FLAGS -o sw/build/bootloader.elf @SOURCES

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bootloader compilation failed!"
    exit 1
}

& $OBJCOPY -O binary sw/build/bootloader.elf sw/build/bootloader.bin
& $OBJDUMP -d sw/build/bootloader.elf > sw/build/bootloader.dis

# Generate memory initialization files for FPGA BRAM synthesis
python sw/build/make_hex.py sw/build/bootloader.bin sw/build/instructions.mem
Copy-Item sw/build/instructions.mem rtl/core/instructions.mem -Force -ErrorAction SilentlyContinue
Copy-Item sw/build/instructions.mem sim/programs/boot_stub.mem -Force -ErrorAction SilentlyContinue

Write-Host "[OK] Bootloader compiled: sw/build/bootloader.elf"
& $SIZE sw/build/bootloader.elf
