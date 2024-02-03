#pragma once
#include "string_utils.h"

#define EXE_MODULE_SELECTED (1 << 0)

typedef struct {
    String name;
    String demangled_name;
} InstrumentedProcedure;

typedef struct {
    String   name;
    int      proc_count;
    InstrumentedProcedure*  procedures;
    uint32_t flags;
} ExeModule;

typedef struct {
    ExeModule* modules;
} Table;

typedef enum {
    ctEnd = 0,
    ctRequestProcedures = 1, 
    ctInstrumetProcedures = 2, 
    ctProfilingData = 3,
} PipeMessage;

extern Table g_module_table;

int  antipessimizer_start(const char* filepath);
int  antipessimizer_load_exe(const char* filepath);
void antipessimizer_request_result();
void read_pipe_message();
int  antipessimizer_stop();