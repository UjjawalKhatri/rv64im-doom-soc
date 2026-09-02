# ============================================================================
# File: run_core_sim.ps1
# Description: Compiles and runs the RV64I core processor testbench (tb_rv64i_core)
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

# Collect RTL and core testbench
$core_rtl = Get-ChildItem "rtl/core/*.v" | ForEach-Object { $_.FullName }
$tb_file  = (Resolve-Path "sim/tb/tb_rv64i_core.v").Path

$all_sources = $core_rtl + @($tb_file)

Write-Host "=================================================================="
Write-Host "  Compiling RV64I Core Testbench with xvlog                       "
Write-Host "=================================================================="
& $xvlog -sv @all_sources
if ($LASTEXITCODE -ne 0) { throw "xvlog compilation failed" }

Write-Host "=================================================================="
Write-Host "  Elaborating snapshot with xelab                                 "
Write-Host "=================================================================="
& $xelab -debug typical tb_rv64i_core -s tb_rv64i_core_sim
if ($LASTEXITCODE -ne 0) { throw "xelab elaboration failed" }

Write-Host "=================================================================="
Write-Host "  Running Simulation with xsim                                    "
Write-Host "=================================================================="
& $xsim tb_rv64i_core_sim -runall
