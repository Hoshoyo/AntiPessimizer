#pragma once
extern "C" {
#include "string_utils.h"
}

#define EXE_MODULE_SELECTED (1 << 0)

typedef struct {
    HANDLE handle;
    DWORD  id;
    String debug_name;
} RemoteThread;

typedef struct {
    String name;
    String demangled_name;
    uint32_t offset;
    uint32_t size;
} InstrumentedProcedure;

typedef struct {
    String   name;
    int      proc_count;
    InstrumentedProcedure*  procedures;
    uint32_t flags;
} ExeModule;

typedef struct {
    ExeModule* modules;
} ModuleTable;

typedef enum {
    ctEnd = 0,
    ctRequestProcedures = 1, 
    ctInstrumetProcedures = 2, 
    ctProfilingData = 3,
    ctProfilingDataNoName = 4,
    ctClearResults = 5,
} PipeMessage;

typedef struct {
    String   name;
    uint32_t thread_id;
    uint64_t elapsed_exclusive;
    uint64_t elapsed_inclusive;
    uint64_t hitcount;
    uint64_t address;
} ProfileAnchor;

typedef struct {
    uint64_t cycles_per_second;
    ProfileAnchor* anchors;
} ProfilingResults;

void  antipessimizer_init();
int   antipessimizer_start(const char* filepath);
int   antipessimizer_load_exe(const char* filepath);
void  antipessimizer_request_result();
void* antipessimizer_read_pipe_message();
int   antipessimizer_stop();
void  antipessimizer_clear();
int   antipessimizer_clear_results();
void  antipessimizer_clear_anchors();
void  antipessimizer_save_results();
void* os_file_read(const char* in_filename, int64_t* out_size);
ProfilingResults* antipessimizer_get_profiling_results();
String antipessimizer_get_thread_name(uint32_t id);
ModuleTable* antipessimizer_get_module_table();