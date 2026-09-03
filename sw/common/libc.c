// ============================================================================
// File: libc.c
// Description: Minimal Freestanding C Standard Library for Bare-Metal DOOM
// Provides string, memory, character, formatted I/O, file stubs, and bump allocator
// ============================================================================

#include "libc.h"
#include "../include/soc_regs.h"
#include "../include/vga_text.h"

// Standard file streams
static int dummy_stdin = 1;
static int dummy_stdout = 2;
static int dummy_stderr = 3;

FILE *stdin = (FILE *)&dummy_stdin;
FILE *stdout = (FILE *)&dummy_stdout;
FILE *stderr = (FILE *)&dummy_stderr;

void *__dso_handle = 0;
void *_impure_ptr = 0;

// Ctype array fallback
const char _ctype_[257] = { 0 };

// ============================================================================
// Memory & String Functions
// ============================================================================

void *memcpy(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    while (n--) *d++ = *s++;
    return dest;
}

void *memset(void *s, int c, size_t n) {
    uint8_t *p = (uint8_t *)s;
    while (n--) *p++ = (uint8_t)c;
    return s;
}

void *memmove(void *dest, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
    return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    const uint8_t *p1 = (const uint8_t *)s1;
    const uint8_t *p2 = (const uint8_t *)s2;
    while (n--) {
        if (*p1 != *p2) return *p1 - *p2;
        p1++; p2++;
    }
    return 0;
}

size_t strlen(const char *s) {
    size_t len = 0;
    while (s && *s++) len++;
    return len;
}

char *strcpy(char *dest, const char *src) {
    char *d = dest;
    while ((*d++ = *src++));
    return dest;
}

char *strncpy(char *dest, const char *src, size_t n) {
    char *d = dest;
    while (n > 0 && *src) {
        *d++ = *src++;
        n--;
    }
    while (n > 0) {
        *d++ = '\0';
        n--;
    }
    return dest;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++; s2++;
    }
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
    while (n > 0 && *s1 && (*s1 == *s2)) {
        s1++; s2++; n--;
    }
    if (n == 0) return 0;
    return *(const unsigned char *)s1 - *(const unsigned char *)s2;
}

int strcasecmp(const char *s1, const char *s2) {
    while (*s1 && (tolower(*(const unsigned char *)s1) == tolower(*(const unsigned char *)s2))) {
        s1++; s2++;
    }
    return tolower(*(const unsigned char *)s1) - tolower(*(const unsigned char *)s2);
}

int strncasecmp(const char *s1, const char *s2, size_t n) {
    while (n > 0 && *s1 && (tolower(*(const unsigned char *)s1) == tolower(*(const unsigned char *)s2))) {
        s1++; s2++; n--;
    }
    if (n == 0) return 0;
    return tolower(*(const unsigned char *)s1) - tolower(*(const unsigned char *)s2);
}

char *strchr(const char *s, int c) {
    while (*s) {
        if (*s == (char)c) return (char *)s;
        s++;
    }
    return (c == 0) ? (char *)s : NULL;
}

char *strrchr(const char *s, int c) {
    const char *last = NULL;
    do {
        if (*s == (char)c) last = s;
    } while (*s++);
    return (char *)last;
}

char *strstr(const char *haystack, const char *needle) {
    if (!*needle) return (char *)haystack;
    for (; *haystack; haystack++) {
        if (*haystack == *needle) {
            const char *h = haystack, *n = needle;
            while (*h && *n && (*h == *n)) {
                h++; n++;
            }
            if (!*n) return (char *)haystack;
        }
    }
    return NULL;
}

char *strcat(char *dest, const char *src) {
    char *d = dest;
    while (*d) d++;
    while ((*d++ = *src++));
    return dest;
}

char *strncat(char *dest, const char *src, size_t n) {
    char *d = dest;
    while (*d) d++;
    while (n > 0 && *src) {
        *d++ = *src++;
        n--;
    }
    *d = '\0';
    return dest;
}

char *strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *dup = (char *)malloc(len);
    if (dup) memcpy(dup, s, len);
    return dup;
}

// ============================================================================
// Character Classification & Conversion
// ============================================================================

int isspace(int c) { return (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'); }
int isdigit(int c) { return (c >= '0' && c <= '9'); }
int isalpha(int c) { return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')); }
int isalnum(int c) { return (isalpha(c) || isdigit(c)); }
int isprint(int c) { return (c >= 0x20 && c <= 0x7E); }
int toupper(int c) { return (c >= 'a' && c <= 'z') ? (c - 'a' + 'A') : c; }
int tolower(int c) { return (c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c; }

int atoi(const char *nptr) {
    return (int)atol(nptr);
}

long atol(const char *nptr) {
    while (isspace(*nptr)) nptr++;
    int sign = 1;
    if (*nptr == '-') { sign = -1; nptr++; }
    else if (*nptr == '+') { nptr++; }

    long val = 0;
    while (isdigit(*nptr)) {
        val = val * 10 + (*nptr - '0');
        nptr++;
    }
    return sign * val;
}

int abs(int j) { return (j < 0) ? -j : j; }
long labs(long j) { return (j < 0) ? -j : j; }
double fabs(double x) { return x; }
float fabsf(float x) { return x; }

// ============================================================================
// Formatted Output & File Operations
// ============================================================================

static void fmt_num(char **out, size_t *rem, uint64_t num, int base, int is_signed, int width, int precision, char pad) {
    char buf[32];
    int i = 0;
    int is_neg = 0;

    if (is_signed && (int64_t)num < 0) {
        is_neg = 1;
        num = (uint64_t)(-(int64_t)num);
    }

    if (num == 0) {
        buf[i++] = '0';
    } else {
        while (num > 0) {
            int r = num % base;
            buf[i++] = (r < 10) ? ('0' + r) : ('a' + r - 10);
            num /= base;
        }
    }

    // Precision for integers specifies minimum number of digits (zero-padded)
    while (precision > i && i < 31) {
        buf[i++] = '0';
    }

    // Sign accounts for 1 character of width
    int total_len = i + (is_neg ? 1 : 0);

    // If padding with space, output spaces BEFORE the sign
    if (pad != '0') {
        while (width > total_len) {
            if (*rem > 1) { *(*out)++ = ' '; (*rem)--; }
            width--;
        }
    }

    if (is_neg) {
        if (*rem > 1) { *(*out)++ = '-'; (*rem)--; }
    }

    // If padding with zero, output zeros AFTER the sign
    if (pad == '0') {
        while (width > total_len) {
            if (*rem > 1) { *(*out)++ = '0'; (*rem)--; }
            width--;
        }
    }

    while (i > 0) {
        if (*rem > 1) { *(*out)++ = buf[--i]; (*rem)--; }
        else i--;
    }
}

int vsnprintf(char *str, size_t size, const char *format, va_list ap) {
    if (!str || size == 0) return 0;
    char *out = str;
    size_t rem = size;

    while (*format && rem > 1) {
        if (*format != '%') {
            *out++ = *format++;
            rem--;
            continue;
        }
        format++; // skip '%'

        char pad = ' ';
        int width = 0;
        int precision = -1;

        // Flags
        while (*format == '0' || *format == '-' || *format == '+' || *format == ' ') {
            if (*format == '0') pad = '0';
            format++;
        }

        // Width
        while (isdigit(*format)) {
            width = width * 10 + (*format - '0');
            format++;
        }

        // Precision
        if (*format == '.') {
            format++;
            precision = 0;
            while (isdigit(*format)) {
                precision = precision * 10 + (*format - '0');
                format++;
            }
        }

        // Length modifiers (skip 'l', 'h', 'z', etc.)
        while (*format == 'l' || *format == 'h' || *format == 'z') {
            format++;
        }

        switch (*format) {
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (!s) s = "(null)";
                int count = 0;
                while (*s && rem > 1 && (precision < 0 || count < precision)) {
                    *out++ = *s++;
                    rem--;
                    count++;
                }
                while (width > count && rem > 1) {
                    *out++ = ' ';
                    rem--;
                    width--;
                }
                break;
            }
            case 'd':
            case 'i':
                fmt_num(&out, &rem, (uint64_t)va_arg(ap, int), 10, 1, width, precision, pad);
                break;
            case 'u':
                fmt_num(&out, &rem, (uint64_t)va_arg(ap, unsigned int), 10, 0, width, precision, pad);
                break;
            case 'x':
            case 'X':
            case 'p':
                fmt_num(&out, &rem, (uint64_t)va_arg(ap, uint64_t), 16, 0, width, precision, pad);
                break;
            case 'c':
                if (rem > 1) { *out++ = (char)va_arg(ap, int); rem--; }
                break;
            case '%':
                if (rem > 1) { *out++ = '%'; rem--; }
                break;
            default:
                if (rem > 1) { *out++ = *format; rem--; }
                break;
        }
        format++;
    }
    *out = '\0';
    return (int)(out - str);
}

int snprintf(char *str, size_t size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, size, format, ap);
    va_end(ap);
    return ret;
}

int sprintf(char *str, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int ret = vsnprintf(str, 65536, format, ap);
    va_end(ap);
    return ret;
}

int vsprintf(char *str, const char *format, va_list ap) {
    return vsnprintf(str, 65536, format, ap);
}

#include "../include/uart.h"

int putchar(int c) {
    uart_putc((char)c);
    return c;
}

int fputc(int c, FILE *stream) {
    (void)stream;
    uart_putc((char)c);
    return c;
}

int puts(const char *s) {
    uart_puts(s);
    uart_putc('\n');
    return 0;
}

int fputs(const char *s, FILE *stream) {
    (void)stream;
    uart_puts(s);
    return 0;
}

int printf(const char *format, ...) {
    char buf[512];
    va_list ap;
    va_start(ap, format);
    int len = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    uart_puts(buf);
    return len;
}

int fprintf(FILE *stream, const char *format, ...) {
    (void)stream;
    char buf[512];
    va_list ap;
    va_start(ap, format);
    int len = vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    uart_puts(buf);
    return len;
}

int sscanf(const char *str, const char *format, ...) {
    // Minimal sscanf for integer parameters
    va_list ap;
    va_start(ap, format);
    int count = 0;
    while (*format && *str) {
        if (*format == '%' && *(format + 1) == 'd') {
            int *val = va_arg(ap, int *);
            *val = atoi(str);
            count++;
            format += 2;
            while (isdigit(*str) || *str == '-') str++;
        } else {
            format++;
            str++;
        }
    }
    va_end(ap);
    return count;
}

int remove(const char *pathname) { (void)pathname; return 0; }
int rename(const char *oldpath, const char *newpath) { (void)oldpath; (void)newpath; return 0; }
int mkdir(const char *pathname, int mode) { (void)pathname; (void)mode; return 0; }
int system(const char *command) { (void)command; return 0; }
int *__errno(void) { static int err = 0; return &err; }

double atof(const char *nptr) {
    (void)nptr;
    return 0;
}

int vfprintf(FILE *stream, const char *format, va_list ap) {
    (void)stream;
    char buf[512];
    int len = vsnprintf(buf, sizeof(buf), format, ap);
    vga_text_puts(buf);
    return len;
}

FILE *fopen(const char *pathname, const char *mode) { (void)pathname; (void)mode; return NULL; }
int fclose(FILE *stream) { (void)stream; return 0; }
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) { (void)ptr; (void)size; (void)nmemb; (void)stream; return 0; }
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) { (void)ptr; (void)size; (void)nmemb; (void)stream; return size * nmemb; }
int fseek(FILE *stream, long offset, int whence) { (void)stream; (void)offset; (void)whence; return 0; }
long ftell(FILE *stream) { (void)stream; return 0; }
int fflush(FILE *stream) { (void)stream; return 0; }

// ============================================================================
// Startup Bump Allocator (for allocations prior to/outside Zone Memory)
// ============================================================================
#define HEAP_SIZE (512 * 1024)
static uint8_t heap_pool[HEAP_SIZE] __attribute__((aligned(16)));
static size_t heap_offset = 0;

void *malloc(size_t size) {
    size = (size + 15) & ~15;
    if (heap_offset + size > HEAP_SIZE) {
        return NULL;
    }
    void *ptr = (void *)&heap_pool[heap_offset];
    heap_offset += size;
    return ptr;
}

void free(void *ptr) {
    (void)ptr;
}

void *calloc(size_t nmemb, size_t size) {
    size_t total = nmemb * size;
    void *ptr = malloc(total);
    if (ptr) memset(ptr, 0, total);
    return ptr;
}

void *realloc(void *ptr, size_t size) {
    if (!ptr) return malloc(size);
    void *new_ptr = malloc(size);
    if (new_ptr) memcpy(new_ptr, ptr, size);
    return new_ptr;
}

void exit(int status) {
    *(volatile uint64_t *)0x10001008ULL = 0xEFULL;
    printf("[EXIT] System halt with status %d\n", status);
    while (1) ;
}

void abort(void) {
    printf("[ABORT] System abort triggered!\n");
    while (1) ;
}
