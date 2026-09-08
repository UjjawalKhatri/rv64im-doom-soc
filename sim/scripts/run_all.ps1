# ============================================================================
# File: run_all.ps1
# Description: Runs every simulation regression in order and prints one
#              combined PASS/FAIL summary. This is the single entry point --
#              a new contributor should not need to know which script depends
#              on which.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File sim/scripts/run_all.ps1
#
# Vivado location is resolved the same way as the individual scripts:
#   $env:VIVADO_DIR  ->  vivado on PATH  ->  C:\Xilinx\Vivado\2022.1\bin
#
# Verified against Vivado 2022.1 and the RISC-V GCC toolchain listed in
# docs/BRINGUP_GUIDE.md.
# ============================================================================
$ErrorActionPreference = "Continue"

$DEFAULT_VIVADO_BIN = "C:\Xilinx\Vivado\2022.1\bin"
if ($env:VIVADO_DIR) {
    $VIVADO_BIN = $env:VIVADO_DIR
} elseif (Get-Command vivado -ErrorAction SilentlyContinue) {
    $VIVADO_BIN = Split-Path (Get-Command vivado).Source
} else {
    $VIVADO_BIN = $DEFAULT_VIVADO_BIN
}
$xvlog = Join-Path $VIVADO_BIN "xvlog.bat"
$xelab = Join-Path $VIVADO_BIN "xelab.bat"
$xsim  = Join-Path $VIVADO_BIN "xsim.bat"

$REPO_ROOT = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $REPO_ROOT

if (-not (Test-Path $xvlog)) {
    Write-Host "ERROR: Vivado not found at $VIVADO_BIN" -ForegroundColor Red
    Write-Host "       Set VIVADO_DIR or put vivado on PATH."
    exit 1
}

$results = [ordered]@{}

function Invoke-Sim {
    param(
        [string]   $Name,
        [string[]] $Sources,
        [string]   $Top,
        [string]   $PassPattern
    )
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host "  $Name" -ForegroundColor Cyan
    Write-Host "=================================================================="

    # Each run gets a clean work library; two xsim runs sharing xsim.dir can
    # deadlock on the work library lock.
    Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue

    & $xvlog @Sources 2>&1 | Select-String "^ERROR" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    if ($LASTEXITCODE -ne 0) { $script:results[$Name] = "FAIL (compile)"; return }

    & $xelab $Top -s "sim_$Top" 2>&1 | Select-String "^ERROR" | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    if ($LASTEXITCODE -ne 0) { $script:results[$Name] = "FAIL (elaborate)"; return }

    $out = & $xsim "sim_$Top" -runall 2>&1
    $out | Select-String -Pattern "PASS|FAIL|SUCCESS|CRASH|Retired|CPI|CHECKS" | ForEach-Object { Write-Host "  $_" }

    if ($out | Select-String -Pattern $PassPattern -Quiet) {
        $script:results[$Name] = "PASS"
    } else {
        $script:results[$Name] = "FAIL"
    }
}

$core_rtl  = Get-ChildItem "rtl/core/*.v"        | ForEach-Object { $_.FullName }
$periph_rtl= Get-ChildItem "rtl/peripherals/*.v" | ForEach-Object { $_.FullName }
# doom_soc_top and clk_gen instantiate Xilinx primitives / the PS7 block design,
# so they are excluded from the RTL-only regressions.
$soc_rtl   = Get-ChildItem "rtl/soc/*.v" |
             Where-Object { $_.Name -notin @('doom_soc_top.v','ps7_wrapper.v','clk_gen.v') } |
             ForEach-Object { $_.FullName }

# 1. RV64IM core -- Fibonacci program, checks retired-instruction count and CPI
Invoke-Sim -Name "Core pipeline (tb_rv64i_core)" `
           -Sources ($core_rtl + @("sim/tb/tb_rv64i_core.v")) `
           -Top "tb_rv64i_core" `
           -PassPattern "Retired Instructions Count\s*:\s*169"

# 2. Minimal SoC -- the jal/forwarding regressions that caught the pipeline bugs
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Minimal SoC (tb_doom_min)" -ForegroundColor Cyan
Write-Host "=================================================================="
Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue
$min = & powershell -ExecutionPolicy Bypass -File sim/scripts/run_min_sim.ps1 2>&1
$min | Select-String -Pattern "PASS|FAIL|SUCCESS|CRASH" | ForEach-Object { Write-Host "  $_" }
if (($min | Select-String -Pattern "SUCCESS" -Quiet) -and
    -not ($min | Select-String -Pattern "CRASH" -Quiet)) {
    $results["Minimal SoC (tb_doom_min)"] = "PASS"
} else {
    $results["Minimal SoC (tb_doom_min)"] = "FAIL"
}

# 3. Peripherals + interconnect, including the VGA scanout path
Invoke-Sim -Name "Peripherals (tb_soc_periph)" `
           -Sources ($core_rtl + $periph_rtl + $soc_rtl + @("sim/tb/tb_soc_periph.v")) `
           -Top "tb_soc_periph" `
           -PassPattern "ALL SOC PERIPHERAL TESTS PASSED"

# 4. VGA pixel-clock divider at all three supported fabric clocks
Invoke-Sim -Name "VGA divider (tb_vga_div)" `
           -Sources @("rtl/peripherals/vga_timing.v", "sim/tb/tb_vga_div.v") `
           -Top "tb_vga_div" `
           -PassPattern "ALL CHECKS PASSED"

Remove-Item -Recurse -Force xsim.dir -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  REGRESSION SUMMARY" -ForegroundColor Cyan
Write-Host "=================================================================="
$failed = 0
foreach ($k in $results.Keys) {
    $v = $results[$k]
    if ($v -eq "PASS") {
        Write-Host ("  {0,-34} {1}" -f $k, $v) -ForegroundColor Green
    } else {
        Write-Host ("  {0,-34} {1}" -f $k, $v) -ForegroundColor Red
        $failed++
    }
}
Write-Host "=================================================================="
if ($failed -eq 0) {
    Write-Host "  ALL REGRESSIONS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "  $failed REGRESSION(S) FAILED" -ForegroundColor Red
    exit 1
}
