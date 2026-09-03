// ============================================================================
// File: doom_main.c
// Description: Main entry point for DOOM executing from DDR3 on RV64IM SoC
// Initializes DoomGeneric engine and enters the main game loop
// ============================================================================

#include "doomgeneric.h"

static char *default_argv[] = {"doom", "-nosound", "-nomusic", "-nosfx", 0};

#include "soc_regs.h"

int main(void) {
    // Milestone 0x01 (LD0 ON): Entered main()
    TRACE(0x01);

    // Initialize DoomGeneric with default arguments
    doomgeneric_Create(4, default_argv);

    // Run game loop
    while (1) {
        doomgeneric_Tick();
    }

    return 0;
}
