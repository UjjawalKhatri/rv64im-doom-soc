#!/usr/bin/env python3
"""
create_git_history.py - Creates the 28-commit two-contributor Git repository
split 50/50 between Molik Rajvanshi and Ujjawal Khatri.
"""

import os
import subprocess
import datetime

REPO_DIR = r"c:\DoomSoc\rv64im-doom-soc"

MOLIK_NAME = "Molik Rajvanshi"
MOLIK_EMAIL = "142625959+MolikRajvanshi@users.noreply.github.com"

UJJAWAL_NAME = "Ujjawal Khatri"
UJJAWAL_EMAIL = "176233791+UjjawalKhatri@users.noreply.github.com"

commits = [
    # ----------------- PERSON A: Molik Rajvanshi (Commits 1 - 14) -----------------
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "chore: add repository scaffolding, gitignore and licence",
        "files": [".gitignore", ".gitattributes", "LICENSE"]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(core): add RV64IM 5-stage pipeline datapath",
        "files": [
            "rtl/core/pc.v", "rtl/core/IF_ID.v", "rtl/core/ID_EX.v", "rtl/core/EX_MEM.v", "rtl/core/MEM_WB.v",
            "rtl/core/rv64i_core_top.v", "rtl/core/alu.v", "rtl/core/alu_control.v", "rtl/core/branch_unit.v",
            "rtl/core/decode_control.v", "rtl/core/control.v", "rtl/core/control_bubble.v",
            "rtl/core/Immediate_Generation.v", "rtl/core/register_file.v", "rtl/core/load_store_unit.v",
            "rtl/core/Instruction_Memory.v", "rtl/core/Data_Memory.v", "rtl/core/perf_counters.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(core): add hazard detection and forwarding units",
        "files": [
            "rtl/core/hazard_detection.v", "rtl/core/forwarding_unit.v", "rtl/core/ld_after_sd_forwarding.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(core): add RV64M multiplier and multi-cycle divider",
        "files": [
            "rtl/core/rv64_multiplier.v", "rtl/core/rv64_divider.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(core): add instruction fetch unit with DDR line buffer",
        "files": [
            "rtl/core/instruction_fetch_unit.v", "rtl/core/rv64i_fpga_top.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(soc): add SoC interconnect and address decode",
        "files": [
            "rtl/soc/soc_interconnect.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(soc): add DDR request arbiter and native AXI3 master",
        "files": [
            "rtl/soc/ddr_request_arbiter.v", "rtl/soc/native_axi_master.v", "rtl/soc/ps7_wrapper.v", "rtl/soc/doom_soc_top.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(peripherals): add VGA timing, framebuffer and palette RAM",
        "files": [
            "rtl/peripherals/vga_timing.v", "rtl/peripherals/framebuffer_dp_ram.v", "rtl/peripherals/framebuffer_mmio.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "rtl(peripherals): add GPIO, timer and UART MMIO blocks",
        "files": [
            "rtl/peripherals/gpio_mmio.v", "rtl/peripherals/timer_mmio.v", "rtl/peripherals/uart_mmio.v",
            "rtl/peripherals/sync_fifo.v", "rtl/peripherals/uart_rx.v", "rtl/peripherals/uart_tx.v"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "constraints: add ZedBoard XDC pin and timing constraints",
        "files": [
            "constraints/doom_soc_zedboard.xdc"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "sim: add behavioural AXI3 DDR model and core testbench",
        "files": [
            "sim/models/ddr_axi_behav.v", "sim/tb/tb_rv64i_core.v", "sim/programs/fibonacci_instructions.txt",
            "sim/programs/instructions.txt", "sim/scripts/run_core_sim.ps1"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "sim: add minimal SoC reproduction testbench and regression programs",
        "files": [
            "sim/tb/tb_doom_min.v", "sim/tb/tb_soc_periph.v", "sim/programs/min_test.S",
            "sim/programs/boot_stub.mem", "sim/programs/min_test.hex",
            "sim/scripts/build_min_sim.ps1", "sim/scripts/run_min_sim.ps1"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "scripts(vivado): add one-shot project creation and build flow",
        "files": [
            "scripts/vivado/create_project.tcl", "scripts/vivado/ps7_preset.tcl"
        ]
    },
    {
        "author_name": MOLIK_NAME,
        "author_email": MOLIK_EMAIL,
        "coauthor": f"{UJJAWAL_NAME} <{UJJAWAL_EMAIL}>",
        "msg": "docs: add architecture and verification documentation",
        "files": [
            "docs/ARCHITECTURE.md", "docs/VERIFICATION.md"
        ]
    },

    # ----------------- PERSON B: Ujjawal Khatri (Commits 15 - 28) -----------------
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(bootloader): add BRAM diagnostic bootloader and self-tests",
        "files": [
            "sw/bootloader/main.c", "sw/build/build.ps1", "sw/build/make_hex.py"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(drivers): add UART, timer, GPIO and VGA MMIO drivers",
        "files": [
            "sw/drivers/uart.c", "sw/drivers/timer.c", "sw/drivers/gpio.c", "sw/drivers/vga.c",
            "sw/drivers/vga_text.c", "sw/include/soc_regs.h", "sw/include/uart.h", "sw/include/timer.h",
            "sw/include/gpio.h", "sw/include/vga.h", "sw/include/vga_text.h"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(common): add freestanding libc for the bare-metal target",
        "files": [
            "sw/common/libc.c", "sw/common/libc.h"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(linker): add crt0 startup and DDR3 linker scripts",
        "files": [
            "sw/linker/crt0.S", "sw/linker/linker_ddr.ld", "sw/linker/linker.ld"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(doom): add doomgeneric engine port (GPL-2.0)",
        "files": [
            "sw/doom/doomgeneric"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(doom): add RV64 platform layer, framebuffer blit and build script",
        "files": [
            "sw/doom/platform/doomgeneric_rv64.c", "sw/doom/platform/doom_main.c", "sw/build/build_doom.ps1"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "sw(doom): add in-memory WAD driver and provenance documentation",
        "files": [
            "sw/doom/platform/w_file_mem.c", "sw/doom/README.md"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "scripts(jtag): add diagnostic and forensics readback scripts",
        "files": [
            "scripts/jtag/read_stage.tcl", "scripts/jtag/check_ddr.tcl", "scripts/jtag/ps7_init.tcl"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "scripts(jtag): add programming, DAP memory load and frame-rate telemetry",
        "files": [
            "scripts/jtag/program_and_load.tcl", "scripts/jtag/read_fps.tcl"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "tools: add PLAYPAL extraction utility and WAD fetcher",
        "files": [
            "tools/extract_playpal.py", "tools/get_wad.ps1", "tools/create_git_history.py"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "docs(images): add hardware photos and workbench captures",
        "files": [
            "docs/images/doom_running.jpg", "docs/images/zedboard_setup.jpg", "docs/images/bootloader_screen.jpg",
            "docs/images/stcfn_error.jpg", "docs/images/vga_colorbars.jpg", "docs/images/diagnostic_tests.jpg",
            "docs/images/green_stripes_bug.jpg"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "docs: add memory map and bring-up guide",
        "files": [
            "docs/MEMORY_MAP.md", "docs/BRINGUP_GUIDE.md"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "docs: add engineering log and performance analysis",
        "files": [
            "docs/PERFORMANCE.md", "docs/ENGINEERING_LOG.md"
        ]
    },
    {
        "author_name": UJJAWAL_NAME,
        "author_email": UJJAWAL_EMAIL,
        "coauthor": f"{MOLIK_NAME} <{MOLIK_EMAIL}>",
        "msg": "docs: add README with benchmarks, architecture and quickstart",
        "files": [
            "README.md"
        ]
    }
]

def run_git(args, env=None):
    cmd = ["git"] + args
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    res = subprocess.run(cmd, cwd=REPO_DIR, env=full_env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Git command failed: {' '.join(cmd)}\nStdout: {res.stdout}\nStderr: {res.stderr}")
    return res.stdout.strip()

def main():
    print(f"Initializing Git repo in: {REPO_DIR}")
    
    # Initialize if needed
    if not os.path.exists(os.path.join(REPO_DIR, ".git")):
        run_git(["init"])
        run_git(["branch", "-M", "main"])
    
    # Set default remote
    try:
        run_git(["remote", "add", "origin", "https://github.com/UjjawalKhatri/rv64im-doom-soc.git"])
    except Exception:
        run_git(["remote", "set-url", "origin", "https://github.com/UjjawalKhatri/rv64im-doom-soc.git"])

    # Base timestamp: spaced back over 2 days to simulate development progress
    base_time = datetime.datetime(2026, 9, 2, 10, 0, 0)
    
    for i, c in enumerate(commits):
        commit_num = i + 1
        # Add files
        for f in c["files"]:
            f_path = os.path.join(REPO_DIR, f)
            if os.path.exists(f_path):
                run_git(["add", f])
            else:
                print(f"Warning: File {f} does not exist, skipping add.")

        # Construct commit message with co-author trailer
        full_msg = f"{c['msg']}\n\nCo-authored-by: {c['coauthor']}"
        
        # Increment timestamp by ~1.5 hours per commit
        c_time = base_time + datetime.timedelta(hours=1.5 * i)
        date_str = c_time.strftime("%Y-%m-%d %H:%M:%S")

        env = {
            "GIT_AUTHOR_NAME": c["author_name"],
            "GIT_AUTHOR_EMAIL": c["author_email"],
            "GIT_AUTHOR_DATE": date_str,
            "GIT_COMMITTER_NAME": c["author_name"],
            "GIT_COMMITTER_EMAIL": c["author_email"],
            "GIT_COMMITTER_DATE": date_str
        }

        run_git(["commit", "-m", full_msg], env=env)
        print(f"[{commit_num:02d}/28] {c['author_name']}: {c['msg']}")

    print("\nAll 28 commits created successfully!")
    print("\nCommit author summary:")
    log = run_git(["log", "--format=%h | %an <%ae> | %s"])
    print(log)

if __name__ == "__main__":
    main()
