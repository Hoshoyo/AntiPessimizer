#pragma once
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#define MAX_PATH 1024
#endif

#define MIN(A, B) (((A) < (B)) ? (A) : (B))
#define MAX(A, B) (((A) > (B)) ? (A) : (B))

bool file_exists(const char* path);
double cycles_to_ms(uint64_t cycles, uint64_t cycles_per_second);
void os_browse_file(char* buffer, int size);