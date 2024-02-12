#include "os.h"

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