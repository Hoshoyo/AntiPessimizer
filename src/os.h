#pragma once
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#define MAX_PATH 1024
#endif

bool file_exists(const char* path);
double cycles_to_ms(uint64_t cycles, uint64_t cycles_per_second);