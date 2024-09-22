#include "os.h"
#include <windows.h>

bool file_exists(const char* path)
{
    DWORD dwAttrib = GetFileAttributesA(path);

    return (dwAttrib != INVALID_FILE_ATTRIBUTES &&
        !(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}

double
cycles_to_ms(uint64_t cycles, uint64_t cycles_per_second)
{
    return ((double)cycles / (double)cycles_per_second) * 1000.0;
}

double
cycles_to_us(uint64_t cycles, uint64_t cycles_per_second)
{
	return ((double)cycles / (double)cycles_per_second) * 1000000.0;
}

double
cycles_to_ns(uint64_t cycles, uint64_t cycles_per_second)
{
	return ((double)cycles / (double)cycles_per_second) * 10000000000.0;
}

double
cycles_to_s(uint64_t cycles, uint64_t cycles_per_second)
{
	return ((double)cycles / (double)cycles_per_second);
}

void
os_browse_file(char* buffer, int size)
{
    OPENFILENAMEA fn = { 0 };
    fn.lStructSize = sizeof(OPENFILENAMEA);
    fn.lpstrFile = buffer;
    fn.nMaxFile = size;
    fn.Flags = OFN_NOCHANGEDIR | OFN_READONLY;

    if (GetOpenFileNameA(&fn) == TRUE)
    {
    }
}

uint32_t os_file_write(const char* filename, void* mem, uint32_t size)
{
	void* fhandle = CreateFileA(filename, GENERIC_WRITE, 0, 0, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
	if (fhandle != INVALID_HANDLE_VALUE)
	{
		DWORD written = 0;
		if (WriteFile(fhandle, mem, size, &written, 0))
		{
			CloseHandle(fhandle);
			return written;
		}
		CloseHandle(fhandle);
	}
	return 0;
}

uint32_t os_file_append(const char* filename, void* mem, uint32_t size)
{
	void* fhandle = CreateFileA(filename, GENERIC_WRITE, 0, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
	if (fhandle != INVALID_HANDLE_VALUE)
	{
		LARGE_INTEGER zero = { 0 };
		if (SetFilePointerEx(fhandle, zero, 0, FILE_END))
		{
			DWORD written = 0;
			if (WriteFile(fhandle, mem, size, &written, 0))
			{
				CloseHandle(fhandle);
				return written;
			}
		}
		CloseHandle(fhandle);
	}
	return 0;
}

void os_datetime(OS_Datetime* systime)
{
	GetSystemTime((SYSTEMTIME*)systime);
}

void* os_file_read(const char* in_filename, int64_t* out_size)
{
	void* fhandle = CreateFileA(in_filename, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
	if (fhandle != INVALID_HANDLE_VALUE)
	{
		uint64_t file_size = 0;
		GetFileSizeEx(fhandle, (LARGE_INTEGER*)&file_size);
		void* mem = calloc(1, file_size);
		const unsigned int max_chunk = 0xffffffff;
		if (mem)
		{
			if (file_size > max_chunk)
			{
				uint64_t total_read = 0;
				uint64_t to_read = file_size;
				do {
					uint32_t chunk_size = (to_read > max_chunk) ? max_chunk : (uint32_t)to_read;
					DWORD bytes_read;

					if (ReadFile(fhandle, mem, chunk_size, &bytes_read, 0))
					{
						to_read -= bytes_read;
						total_read += bytes_read;
					}
					else
						break;
				} while (to_read > 0);
				if (out_size) *out_size = (int64_t)total_read;
				CloseHandle(fhandle);
				return mem;
			}
			else
			{
				DWORD bytes_read;
				if (ReadFile(fhandle, mem, (uint32_t)file_size, &bytes_read, 0))
				{
					if (out_size) *out_size = bytes_read;
					CloseHandle(fhandle);
					return mem;
				}
				CloseHandle(fhandle);
			}
		}
	}
	return 0;
}

bool os_file_exists(char* filepath)
{
	DWORD dwAttrib = GetFileAttributesA(filepath);

	return (dwAttrib != INVALID_FILE_ATTRIBUTES &&
		!(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}