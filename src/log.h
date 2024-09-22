/* ========================================================================
   Based on from circular buffer example from computer_enhance listing 121.
   Original license:

   (C) Copyright 2023 by Molly Rocket, Inc., All Rights Reserved.

   This software is provided 'as-is', without any express or implied
   warranty. In no event will the authors be held liable for any damages
   arising from the use of this software.

   Please see https://computerenhance.com for more information

   ======================================================================== */

#include <windows.h>
#include <stdint.h>
#include <stdarg.h>

struct CircularBuffer
{
    size_t   count;
    uint8_t* base;
    uint8_t* data;
    uint8_t* at;

    HANDLE file_mapping;
    uint32_t repcount;
};

typedef PVOID virtual_alloc_2(HANDLE, PVOID, SIZE_T, ULONG, ULONG, MEM_EXTENDED_PARAMETER*, ULONG);
typedef PVOID map_view_of_file_3(HANDLE, HANDLE, PVOID, ULONG64, SIZE_T, ULONG, ULONG, MEM_EXTENDED_PARAMETER*, ULONG);

CircularBuffer alloc_circular_buffer(uint64_t minsize, uint64_t repcount);
void print_log(CircularBuffer* buffer, const char* fmt, ...);

#if defined(CIRCULARBUFFER_IMPLEMENTATION)
static uint64_t 
round_to_pow2_size(uint64_t minsize, uint64_t pow2size)
{
    uint64_t result = (minsize + pow2size - 1) & ~(pow2size - 1);
    return result;
}

static void 
unmap_circular_buffer(CircularBuffer* buffer)
{
    for (uint32_t i = 0; i < buffer->repcount; ++i)
    {
        UnmapViewOfFile(buffer->base + i * buffer->count);
    }
}

static void 
free_circular_buffer(CircularBuffer* buffer)
{
    if (buffer)
    {
        if (buffer->file_mapping != INVALID_HANDLE_VALUE)
        {
            unmap_circular_buffer(buffer);
            CloseHandle(buffer->file_mapping);
        }

        *buffer = {0};
    }
}

CircularBuffer
alloc_circular_buffer(uint64_t minsize, uint64_t repcount)
{
    CircularBuffer result = {0};

    SYSTEM_INFO Info;
    GetSystemInfo(&Info);
    uint64_t data_size = round_to_pow2_size(minsize, Info.dwAllocationGranularity);
    uint64_t total_repeated_size = repcount * data_size;

    result.file_mapping = CreateFileMapping(INVALID_HANDLE_VALUE, 0, PAGE_READWRITE, (DWORD)(data_size >> 32), (DWORD)(data_size & 0xffffffff), 0);
    result.repcount = repcount;

    if (result.file_mapping != INVALID_HANDLE_VALUE)
    {
        HMODULE Kernel = LoadLibraryA("kernelbase.dll");
        virtual_alloc_2* VirtualAlloc2 = (virtual_alloc_2*)GetProcAddress(Kernel, "VirtualAlloc2");
        map_view_of_file_3* MapViewOfFile3 = (map_view_of_file_3*)GetProcAddress(Kernel, "MapViewOfFile3");

        if (VirtualAlloc2 && MapViewOfFile3)
        {
            uint8_t* base_ptr = (uint8_t*)VirtualAlloc2(0, 0, total_repeated_size, MEM_RESERVE | MEM_RESERVE_PLACEHOLDER, PAGE_NOACCESS, 0, 0);

            bool mapped = true;
            for (uint32_t i = 0; i < repcount; ++i)
            {
                VirtualFree(base_ptr + i * data_size, data_size, MEM_RELEASE | MEM_PRESERVE_PLACEHOLDER);
                if (!MapViewOfFile3(result.file_mapping, 0, base_ptr + i * data_size, 0, data_size, MEM_REPLACE_PLACEHOLDER, PAGE_READWRITE, 0, 0))
                {
                    mapped = false;
                }
            }

            if (mapped)
            {
                result.base = base_ptr;
                result.count = data_size;
            }
        }
    }

    if (!result.base)
    {
        free_circular_buffer(&result);
    }

    return result;
}

void
print_log(CircularBuffer* buffer, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    buffer->at += vsprintf((char*)buffer->at, fmt, args);

    if (buffer->at > buffer->data + buffer->count)
        buffer->at -= buffer->count;

    va_end(args);
}
#endif