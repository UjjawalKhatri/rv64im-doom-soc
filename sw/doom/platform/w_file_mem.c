// ============================================================================
// File: w_file_mem.c
// Description: In-Memory WAD Loader for Bare-Metal DOOM on RV64IM ZedBoard SoC
// Reads doom1.wad directly from memory at 0x0100_0000 (DDR WAD Preload Region)
// ============================================================================

#include "w_file.h"
#include "z_zone.h"
#include <string.h>

#define WAD_PRELOAD_BASE 0x81000000ULL
#define WAD_PRELOAD_SIZE 4196020U  // doom1.wad size (4.19 MB)

typedef struct {
    wad_file_t wad;
    const uint8_t *mem_base;
    size_t size;
} mem_wad_file_t;

extern wad_file_class_t mem_wad_file;
extern wad_file_class_t stdc_wad_file;

static wad_file_t *W_Mem_OpenFile(char *path) {
    (void)path;
    mem_wad_file_t *result;

    result = Z_Malloc(sizeof(mem_wad_file_t), PU_STATIC, 0);
    result->wad.file_class = &mem_wad_file;
    result->wad.mapped = (void *)WAD_PRELOAD_BASE;
    result->wad.length = WAD_PRELOAD_SIZE;
    result->mem_base = (const uint8_t *)WAD_PRELOAD_BASE;
    result->size = WAD_PRELOAD_SIZE;

    return &result->wad;
}

static void W_Mem_CloseFile(wad_file_t *wad) {
    Z_Free(wad);
}

size_t W_Mem_Read(wad_file_t *wad, unsigned int offset, void *buffer, size_t buffer_len) {
    mem_wad_file_t *mem_wad = (mem_wad_file_t *)wad;

    if (offset >= mem_wad->size) {
        return 0;
    }

    if (offset + buffer_len > mem_wad->size) {
        buffer_len = mem_wad->size - offset;
    }

    memcpy(buffer, mem_wad->mem_base + offset, buffer_len);
    return buffer_len;
}

wad_file_class_t mem_wad_file = {
    W_Mem_OpenFile,
    W_Mem_CloseFile,
    W_Mem_Read,
};

// Aliased as stdc_wad_file so standard DoomGeneric routes directly to in-memory WAD
wad_file_class_t stdc_wad_file = {
    W_Mem_OpenFile,
    W_Mem_CloseFile,
    W_Mem_Read,
};
