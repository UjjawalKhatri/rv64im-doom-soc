#include <stdio.h>

#include "m_argv.h"

#include "doomgeneric.h"

pixel_t static_screen_buffer[DOOMGENERIC_RESX * DOOMGENERIC_RESY] __attribute__((aligned(16)));
pixel_t* DG_ScreenBuffer = static_screen_buffer;

void M_FindResponseFile(void);
void D_DoomMain (void);

#include "soc_regs.h"

void doomgeneric_Create(int argc, char **argv)
{
    // Milestone 0x02 (LD1 ON): Entered doomgeneric_Create
    TRACE(0x02);

    // save arguments
    myargc = argc;
    myargv = argv;

    // Milestone 0x04 (LD2 ON): Setup complete
    TRACE(0x04);

    DG_ScreenBuffer = static_screen_buffer;

    // Milestone 0x08 (LD3 ON): ScreenBuffer assigned, calling DG_Init
    TRACE(0x08);

    DG_Init();

    // Milestone 0x10 (LD4 ON): After DG_Init, entering D_DoomMain
    TRACE(0x10);

    D_DoomMain ();
}

