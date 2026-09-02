# ============================================================================
# File: run_min_sim.ps1
# Description: Compiles and runs the minimal SoC reproduction testbench (tb_doom_min)
#              in Vivado XSim from the repository root.
# ============================================================================
$ErrorActionPreference = "Stop"

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

# 1. Build the minimal test program hex image
powershell -ExecutionPolicy Bypass -File sim/scripts/build_min_sim.ps1

# 2. Collect RTL and simulation sources
$core_rtl = Get-ChildItem "rtl/core/*.v" | ForEach-Object { $_.FullName }
$soc_rtl  = @(
    (Resolve-Path "rtl/soc/soc_interconnect.v").Path,
    (Resolve-Path "rtl/soc/ddr_request_arbiter.v").Path,
    (Resolve-Path "rtl/soc/native_axi_master.v").Path
)
$tb_files = @(
    (Resolve-Path "sim/models/ddr_axi_behav.v").Path,
    (Resolve-Path "sim/tb/tb_doom_min.v").Path
)

$all_sources = $core_rtl + $soc_rtl + $tb_files

Write-Host "=================================================================="
Write-Host "  Compiling Minimal SoC Testbench with xvlog                      "
Write-Host "=================================================================="
& $xvlog -sv @all_sources
if ($LASTEXITCODE -ne 0) { throw "xvlog compilation failed" }

Write-Host "=================================================================="
Write-Host "  Elaborating snapshot with xelab                                 "
Write-Host "=================================================================="
& $xelab -debug typical tb_doom_min -s tb_doom_min_sim
if ($LASTEXITCODE -ne 0) { throw "xelab elaboration failed" }

Write-Host "=================================================================="
Write-Host "  Running Simulation with xsim                                    "
Write-Host "=================================================================="
& $xsim tb_doom_min_sim -runall
