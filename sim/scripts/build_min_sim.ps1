# ============================================================================
# File: build_min_sim.ps1
# Description: Assembles minimal test program (min_test.S) and converts it to
#              64-bit-word hex format for behavioral DDR memory initialization ($readmemh).
# Produces: sim/programs/min_test.hex
# ============================================================================
$ErrorActionPreference = "Stop"

$DEFAULT_GCC_BIN = "C:\opt\riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-w64-mingw32\bin"
if ($env:RISCV_TOOLCHAIN) {
    $GCC_BIN = $env:RISCV_TOOLCHAIN
} elseif (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $GCC_BIN = Split-Path (Get-Command riscv64-unknown-elf-gcc).Source
} else {
    $GCC_BIN = $DEFAULT_GCC_BIN
}

$CC      = Join-Path $GCC_BIN "riscv64-unknown-elf-gcc.exe"
$OBJCOPY = Join-Path $GCC_BIN "riscv64-unknown-elf-objcopy.exe"

$REPO_ROOT = (Resolve-Path "$PSScriptRoot/../..").Path
$SRC       = Join-Path $REPO_ROOT "sim/programs/min_test.S"
$OUT_ELF   = Join-Path $REPO_ROOT "sim/programs/min_test.elf"
$OUT_BIN   = Join-Path $REPO_ROOT "sim/programs/min_test.bin"
$OUT_HEX   = Join-Path $REPO_ROOT "sim/programs/min_test.hex"

& $CC "-march=rv64im" "-mabi=lp64" "-nostdlib" "-nostartfiles" "-Wl,-Ttext=0x80000000" "-o" $OUT_ELF $SRC
if ($LASTEXITCODE -ne 0) { throw "Assembly failed" }

& $OBJCOPY -O binary $OUT_ELF $OUT_BIN
if ($LASTEXITCODE -ne 0) { throw "Objcopy failed" }

# Convert little-endian binary bytes into 64-bit hex words (one word per line)
$bytes = [System.IO.File]::ReadAllBytes($OUT_BIN)
$pad = (8 - ($bytes.Length % 8)) % 8
if ($pad -gt 0) { $bytes += New-Object byte[] $pad }

$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $bytes.Length; $i += 8) {
    $w = ""
    for ($j = 7; $j -ge 0; $j--) { $w += ("{0:x2}" -f $bytes[$i + $j]) }
    [void]$sb.AppendLine($w)
}
[System.IO.File]::WriteAllText($OUT_HEX, $sb.ToString().TrimEnd() + [System.Environment]::NewLine, [System.Text.Encoding]::ASCII)
Write-Host "[OK] Wrote $OUT_HEX ($([math]::Ceiling($bytes.Length/8)) 64-bit words)"
