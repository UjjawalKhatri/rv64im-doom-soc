// ============================================================================
// File: libc.h
// Description: Minimal Freestanding C Standard Library for Bare-Metal DOOM
// ============================================================================

#ifndef BAREMETAL_LIBC_H
#define BAREMETAL_LIBC_H

#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

// Standard Types & Constants
typedef void * FILE;
extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

// String & Memory Operations
void *memcpy(void *dest, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
void *memmove(void *dest, const void *src, size_t n);
int memcmp(const void *s1, const void *s2, size_t n);

size_t strlen(const char *s);
char *strcpy(char *dest, const char *src);
char *strncpy(char *dest, const char *src, size_t n);
int strcmp(const char *s1, const char *s2);
int strncmp(const char *s1, const char *s2, size_t n);
int strcasecmp(const char *s1, const char *s2);
int strncasecmp(const char *s1, const char *s2, size_t n);
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *haystack, const char *needle);
char *strcat(char *dest, const char *src);
char *strncat(char *dest, const char *src, size_t n);
char *strdup(const char *s);

// Character Classification
int isspace(int c);
int isdigit(int c);
int isalpha(int c);
int isalnum(int c);
int isprint(int c);
int toupper(int c);
int tolower(int c);

// Conversion & Math
int atoi(const char *nptr);
long atol(const char *nptr);
int abs(int j);
long labs(long j);
double fabs(double x);
float fabsf(float x);

// Formatted I/O & File Operations
int sprintf(char *str, const char *format, ...);
int snprintf(char *str, size_t size, const char *format, ...);
int vsprintf(char *str, const char *format, va_list ap);
int vsnprintf(char *str, size_t size, const char *format, va_list ap);
int printf(const char *format, ...);
int fprintf(FILE *stream, const char *format, ...);
int puts(const char *s);
int fputs(const char *s, FILE *stream);
int putchar(int c);
int fputc(int c, FILE *stream);
int sscanf(const char *str, const char *format, ...);

FILE *fopen(const char *pathname, const char *mode);
int fclose(FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int fseek(FILE *stream, long offset, int whence);
long ftell(FILE *stream);
int fflush(FILE *stream);

// Memory Allocation
void *malloc(size_t size);
void free(void *ptr);
void *realloc(void *ptr, size_t size);
void *calloc(size_t nmemb, size_t size);

// Process Control
void exit(int status);
void abort(void);

#endif /* BAREMETAL_LIBC_H */
