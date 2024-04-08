#pragma once
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#define MAX_PATH 1024
#endif

#define MIN(A, B) (((A) < (B)) ? (A) : (B))
#define MAX(A, B) (((A) > (B)) ? (A) : (B))

typedef struct {
	uint16_t year;
	uint16_t month;
	uint16_t day_week;
	uint16_t day;
	uint16_t hour;
	uint16_t minute;
	uint16_t second;
	uint16_t milliseconds;
} OS_Datetime;

bool file_exists(const char* path);
double cycles_to_ms(uint64_t cycles, uint64_t cycles_per_second);
void os_browse_file(char* buffer, int size);
uint32_t os_file_write(const char* filename, void* mem, uint32_t size);
uint32_t os_file_append(const char* filename, void* mem, uint32_t size);
void os_datetime(OS_Datetime* systime);
void* os_file_read(const char* in_filename, int64_t* out_size);
bool os_file_exists(char* filepath);