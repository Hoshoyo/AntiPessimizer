#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <tchar.h>
#include <stdio.h>
#include <psapi.h>
#include <stdint.h>

#include <light_array.h>
#define HPA_IMPLEMENTATION
#include <hpa.h>
#include "os.h"

#define MAX(A, B) (((A) > (B)) ? (A) : (B))
#define MIN(A, B) (((A) < (B)) ? (A) : (B))

extern "C" {
#define UNICODE_CONVERT_IMPLEMENTATION
#include "unicode.h"
#include "string_utils.h"
#include <light_arena.h>
}

#include "antipessimizer.h"
#include "log.h"

#define MEGABYTE (1024*1024)

struct TThrTranslate {
    void* epilogue_jmp;
    void** last_hook_jmp;
    int    thread_index;
    int    res;
    void* patch_rsp;
};

struct Antipessimizer {
    bool loaded_necessary_inject_dlls = false;
    bool started = false;
    bool running = false;
    bool debugging = false;
    bool should_clear = false;

    HANDLE debugged_thread;
    STARTUPINFOA startup_info = { 0 };
    PROCESS_INFORMATION process_info = { 0 };

    uint8_t first_byte = 0;
    DWORD64 entry_point = 0;

    RemoteThread* suspended_threads;
    RemoteThread* remote_threads;

    HANDLE pipe = 0;
    void* send_buffer = 0;
    Light_Arena* recv_buffer = 0;

    DWORD remote_thread_id = 0;
    DWORD remote_worker_id = 0;

    void* loadlibaddr = 0;
    void* sleeplibaddr = 0;

    DWORD dbg_thread_id = 0;

    ProfilingResults prof_results;

    ModuleTable module_table;

    TThrTranslate* remote_thread_translate;
    void* remote_profile_stack;
    uint32_t remote_thread_translate_size;
    uint32_t remote_profile_stack_size;

    String* preselected_units;

    CircularBuffer logbuffer;
};

#define c_ProfilerStackSize (1024*128)

struct TProfileAnchor {
    uint64_t nElapsedExclusive;
    uint64_t nElapsedInclusive;
    uint64_t nHitCount;
    void*    ptrNextAnchors;
    int32_t  nThreadID;
    int32_t  nLine;
    void*    strName;
    void*    pAddr;
};

struct TDHProfileBlock {
    TProfileAnchor* parent_anchor;
    TProfileAnchor* anchor;
    uint64_t        start_time;
    uint64_t        prev_time_inclusive;
    void*           ptr_return_target;
    void*           ptr_last_hook_jmp;
};

struct TDHProfilerStack {
    TDHProfileBlock blocks[c_ProfilerStackSize];
    int64_t  addr_offset;
    int32_t  at_index;
    uint32_t thread_id;
    bool     unwinding;
};

static Antipessimizer antip;

void injectcode(Antipessimizer* antip)
{
    HANDLE process = antip->process_info.hProcess;

    void* base = VirtualAllocEx(process, 0, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (base)
    {
        char antip_path[MAX_PATH] = { 0 };
        DWORD namelen = GetFullPathNameA(".\\Win64\\Debug\\AntiPessimizerDLL.dll", sizeof(antip_path), antip_path, 0);

        if (!os_file_exists(antip_path))
        {
            namelen = GetFullPathNameA(".\\AntiPessimizerDLL.dll", sizeof(antip_path), antip_path, 0);
        }

        SIZE_T written = 0;

        char code[] = {
            0x48, 0x8b, 0x1,                    // mov rax,[rcx]
            0x48, 0x83, 0xc1, 0x8,              // add rcx,$08
            0x4c, 0x8b, 0x11,                   // mov r10, [rcx]
            0x41, 0x52,                         // push r10
            0x48, 0x83, 0xc1, 0x8,              // add rcx,$08
            0x48, 0x83, 0xec, 32,               // sub rsp, 32
            0xff, 0xd0,                         // call rax (LoadLibraryA)
            0x48, 0x83, 0xc4, 32,               // add rsp, 32
            0x5B,                               // pop rbx
            0x48, 0xb9, 0xe8, 0x3, 0,0,0,0,0,0, // at1: mov rcx, 1000
            0xff, 0xd3,                         // call rbx (Sleep)
            0xeb, 0xf2,                         // jmp at1
            0xc3                                // ret

            // 0xeb, 0xfe
        };
        WriteProcessMemory(process, base, code, sizeof(code), &written);

        char* at = (char*)base + 1024;
        WriteProcessMemory(process, at, &antip->loadlibaddr, sizeof(void*), &written);
        at += written;
        WriteProcessMemory(process, at, &antip->sleeplibaddr, sizeof(void*), &written);
        at += written;
        WriteProcessMemory(process, at, antip_path, namelen, &written);
        at += written;

        HANDLE thread_handle = CreateRemoteThread(process, 0, 0, (DWORD(*)(LPVOID))base, (char*)base + 1024, 0, &antip->remote_thread_id);
        printf("Created remote thread %d\n", antip->remote_thread_id);
    }
    else
    {
        printf("Error allocating memory on process\n");
    }
}

typedef struct {
    uint32_t size;
    uint32_t type;
} DebugRequest;

void
send_procedures_request(Antipessimizer* antip)
{
    DWORD written = 0;
    DebugRequest dr = { sizeof(DebugRequest) - sizeof(uint32_t), ctRequestProcedures};
    WriteFile(antip->pipe, &dr, sizeof(dr), &written, 0);
}

void
antipessimizer_request_result()
{
    DWORD written = 0;
    //DebugRequest dr = { sizeof(DebugRequest) - sizeof(uint32_t), ctProfilingDataNoName };
    DebugRequest dr = { sizeof(DebugRequest) - sizeof(uint32_t), ctProfilingData };
    WriteFile(antip.pipe, &dr, sizeof(dr), &written, 0);
}

typedef struct {
    uint32_t type; // must be 0x1000
    char* name;
    uint32_t thread_id;
    uint32_t flags;
} TThreadName;

static HANDLE
find_thread(Antipessimizer* antip, uint32_t id)
{
    for (int i = 0; i < array_length(antip->remote_threads); ++i)
    {
        if (antip->remote_threads[i].id == id)
            return antip->remote_threads[i].handle;
    }
    return INVALID_HANDLE_VALUE;
}

static int32_t
find_profiler_stack_index(Antipessimizer* antip, uint32_t thread_id)
{
    TThrTranslate translate = { 0 };
    SIZE_T read_bytes = 0;
    if (ReadProcessMemory(antip->process_info.hProcess,
        (char*)antip->remote_thread_translate + thread_id * antip->remote_thread_translate_size, &translate, sizeof(translate), &read_bytes))
    {
        return translate.thread_index;
    }
    return -1;
}

struct LocationInfo {
    bool   valid;
    String proc_name;
    String module_name;
};

static LocationInfo
find_proc_name(Antipessimizer* antip, char* addr)
{
    MEMORY_BASIC_INFORMATION meminfo = { 0 };
    VirtualQueryEx(antip->process_info.hProcess, addr, &meminfo, sizeof(meminfo));

    for (int i = 0; i < array_length(antip->module_table.modules); ++i)
    {
        InstrumentedProcedure* procs = antip->module_table.modules[i].procedures;
        if (procs && array_length(procs) > 0)
        {
            for (int p = 0; p < array_length(procs); ++p)
            {
                uint32_t offset = procs[p].offset + 0x1000;
                char* va = (char*)meminfo.AllocationBase + offset;
                uint32_t size = procs[p].size;

                if (addr >= va && addr < (va + size))
                {

                    return { true, procs[p].demangled_name, antip->module_table.modules[i].name };
                }
            }
        }
    }
    return { 0 };
}

static void
remote_trace_stack(Antipessimizer* antip, int32_t pstack_index)
{
    int32_t at_index = -1;

    SIZE_T read_bytes = 0;
    TDHProfilerStack* ps = (TDHProfilerStack*)((char*)antip->remote_profile_stack + antip->remote_profile_stack_size * pstack_index);

    if (ReadProcessMemory(antip->process_info.hProcess, &ps->at_index, &at_index, sizeof(at_index), &read_bytes))
    {
        for (int k = 0; k < 100 && at_index > 0; ++k, --at_index)
        {
            TDHProfileBlock read_block = { 0 };
            TDHProfileBlock* block = ps->blocks + at_index;
            if (!ReadProcessMemory(antip->process_info.hProcess, block, &read_block, sizeof(read_block), &read_bytes))
                break;

            void* ret_addr = read_block.ptr_return_target;

            LocationInfo loc = find_proc_name(antip, (char*)ret_addr);
            print_log(&antip->logbuffer, " | %p %.*s.%.*s\n", ret_addr, loc.module_name.length, loc.module_name.data, loc.proc_name.length, loc.proc_name.data);
        }
    }
}

static void
dump_context(CircularBuffer* logbuffer, CONTEXT* ctx)
{    
    print_log(logbuffer, " - gp registers: ");
    print_log(logbuffer, " RAX: 0x%llx", ctx->Rax);
    print_log(logbuffer, " RBX: 0x%llx", ctx->Rbx);
    print_log(logbuffer, " RCX: 0x%llx", ctx->Rcx);
    print_log(logbuffer, " RDX: 0x%llx", ctx->Rdx);
    print_log(logbuffer, " RSP: 0x%llx", ctx->Rsp);
    print_log(logbuffer, " RBP: 0x%llx", ctx->Rbp);
    print_log(logbuffer, " RSI: 0x%llx", ctx->Rsi);
    print_log(logbuffer, " RDI: 0x%llx", ctx->Rdi);
    print_log(logbuffer, " R8: 0x%llx",  ctx->R8);
    print_log(logbuffer, " R9: 0x%llx",  ctx->R9);
    print_log(logbuffer, " R10: 0x%llx", ctx->R10);
    print_log(logbuffer, " R11: 0x%llx", ctx->R11);
    print_log(logbuffer, " R12: 0x%llx", ctx->R12);
    print_log(logbuffer, " R13: 0x%llx", ctx->R13);
    print_log(logbuffer, " R14: 0x%llx", ctx->R14);
    print_log(logbuffer, " R15: 0x%llx", ctx->R15);
    print_log(logbuffer, " EFLAGS: 0x%llx", ctx->EFlags);
    print_log(logbuffer, "\n");    
}

static const char*
access_violation_string(ULONG_PTR value)
{
    switch (value)
    {
        case 0: return "reading";
        case 1: return "writing";
        case 8: return "executing";
        default: return "-";
    }
}

CircularBuffer*
antipessimizer_get_logbuffer()
{
    return &antip.logbuffer;
}

void
antipessimizer_process_next_debug_event(Antipessimizer* antip, DEBUG_EVENT& dbg_event)
{
    DWORD dwContinueStatus = DBG_CONTINUE;

    switch (dbg_event.dwDebugEventCode)
    {
        case EXCEPTION_DEBUG_EVENT: {
            printf("*** Antipessimizer Exception *** Code=%x Address=0x%llx\n", dbg_event.u.Exception.ExceptionRecord.ExceptionCode,
                dbg_event.u.Exception.ExceptionRecord.ExceptionAddress);
            switch (dbg_event.u.Exception.ExceptionRecord.ExceptionCode)
            {
            case 0x406d1388: { // Name Thread for debugging                
                TThreadName* tname = (TThreadName*)dbg_event.u.Exception.ExceptionRecord.ExceptionInformation;
                char bytes[128] = { 0 };
                SIZE_T read_bytes = 0;
                if (ReadProcessMemory(antip->process_info.hProcess,
                    tname->name, bytes, sizeof(bytes), &read_bytes))
                {
                    bytes[sizeof(bytes)-1] = 0;
                    for (int i = 0; i < array_length(antip->remote_threads); ++i)
                    {
                        if (antip->remote_threads[i].id == dbg_event.dwThreadId)
                        {
                            String dbg_name = ustr_new_c(bytes);
                            antip->remote_threads[i].debug_name = dbg_name;
                            print_log(&antip->logbuffer, "Named thread %d as %s\n", dbg_event.dwThreadId, dbg_name.data);
                            break;
                        }
                    }
                }
            } break;
            case EXCEPTION_BREAKPOINT: {
                CONTEXT thctx = { 0 };
                thctx.ContextFlags = CONTEXT_ALL;                

                if (GetThreadContext(antip->process_info.hThread, &thctx))
                {
                    if (thctx.Rip == (DWORD64)antip->entry_point + 1)
                    {
                        thctx.Rip = thctx.Rip - 1;
                        SetThreadContext(antip->process_info.hThread, &thctx);

                        if (!antip->started)
                        {
                            RemoteThread rt = { antip->process_info.hThread, antip->process_info.dwThreadId };
                            SuspendThread(antip->process_info.hThread);
                            array_push(antip->suspended_threads, rt);
                        }
                    }
                }
            } break;
            case EXCEPTION_ACCESS_VIOLATION: {
                dwContinueStatus = DBG_EXCEPTION_NOT_HANDLED;

                print_log(&antip->logbuffer, "Access violation %s location: 0x%p\n", access_violation_string(dbg_event.u.Exception.ExceptionRecord.ExceptionInformation[0]), dbg_event.u.Exception.ExceptionRecord.ExceptionAddress);

                HANDLE exception_thread = find_thread(antip, dbg_event.dwThreadId);

                int32_t pstack_index = find_profiler_stack_index(antip, dbg_event.dwThreadId);
                if (pstack_index != -1)
                {
                    // Trace information for the location
                    LocationInfo loc = find_proc_name(antip, (char*)dbg_event.u.Exception.ExceptionRecord.ExceptionAddress);
                    print_log(&antip->logbuffer, " | %p %.*s.%.*s\n", dbg_event.u.Exception.ExceptionRecord.ExceptionAddress, 
                            loc.module_name.length, loc.module_name.data, loc.proc_name.length, loc.proc_name.data);

                    // Attempt to get the stack trace information for the profiler.
                    remote_trace_stack(antip, pstack_index);
                }

                if (exception_thread != INVALID_HANDLE_VALUE)
                {
                    CONTEXT thctx = { 0 };
                    thctx.ContextFlags = CONTEXT_ALL;
                    if (GetThreadContext(exception_thread, &thctx))
                    {
                        dump_context(&antip->logbuffer, &thctx);

                        char bytes[64] = { 0 };
                        SIZE_T read_bytes = 0;
                        if (ReadProcessMemory(antip->process_info.hProcess,
                            dbg_event.u.Exception.ExceptionRecord.ExceptionAddress, bytes, sizeof(bytes), &read_bytes))
                        {
                            int x = 0;
                        }
                    }
                }
            } break;
            default: {
                dwContinueStatus = DBG_EXCEPTION_NOT_HANDLED;
            }break;
            }
        } break;
        case CREATE_THREAD_DEBUG_EVENT: {
            printf("Created Thread %d\n", dbg_event.dwThreadId);
            RemoteThread rt = { dbg_event.u.CreateThread.hThread, dbg_event.dwThreadId };
            array_push(antip->remote_threads, rt);

            if (dbg_event.dwThreadId == antip->remote_thread_id)
            {
                // this is the antipessimizer thread, let it run
            }
            else if (GetThreadId(dbg_event.u.CreateThread.hThread) == GetThreadId(antip->process_info.hThread))
            {
                // this is the main thread, let it run until it is stopped at the entry point
            }
            else if (!antip->started)
            {
                // this is any other thread, just suspend until antipessimizer is ready                
                array_push(antip->suspended_threads, rt);
                SuspendThread(dbg_event.u.CreateThread.hThread);
            }
        } break;
        case CREATE_PROCESS_DEBUG_EVENT: {
            printf("Created process base %p Thread %d\n", dbg_event.u.CreateProcessInfo.lpBaseOfImage, dbg_event.dwThreadId);

            RemoteThread rt = { dbg_event.u.CreateProcessInfo.hThread, dbg_event.dwThreadId };
            array_push(antip->remote_threads, rt);

            SuspendThread(dbg_event.u.CreateProcessInfo.hThread);
            antip->entry_point = (DWORD64)dbg_event.u.CreateProcessInfo.lpStartAddress;

            SIZE_T read_bytes = 0;
            if (ReadProcessMemory(dbg_event.u.CreateProcessInfo.hProcess,
                dbg_event.u.CreateProcessInfo.lpStartAddress, &antip->first_byte, 1, &read_bytes))
            {
                uint8_t int8 = 0xcc;
                SIZE_T written_bytes = 0;
                if (WriteProcessMemory(antip->process_info.hProcess,
                    (LPVOID)antip->entry_point, &int8, 1, &written_bytes))
                {
                    ResumeThread(dbg_event.u.CreateProcessInfo.hThread);
                }
            }
        } break;
        case EXIT_THREAD_DEBUG_EVENT: {
            printf("Exit thread %d\n", dbg_event.dwThreadId);
        } break;
        case UNLOAD_DLL_DEBUG_EVENT:
            break;
        case OUTPUT_DEBUG_STRING_EVENT: {
            SIZE_T bytesread = 0;
            char buffer[4096] = { 0 };
            ReadProcessMemory(antip->process_info.hProcess,
                dbg_event.u.DebugString.lpDebugStringData, buffer, MIN(dbg_event.u.DebugString.nDebugStringLength, 4096), &bytesread);
            printf("%.*s\n", (int)bytesread, buffer);

            const char* at = buffer;
            int klen = hpa_parse_keyword(&at, "AntiPessimizerStartup");
            if (klen > 0)
            {
                hpa_parse_whitespace(&at);
                int rem_worker_id = hpa_parse_int32(&at);

                antip->remote_worker_id = (DWORD)rem_worker_id;

                for (int i = 0; i < array_length(antip->suspended_threads); ++i) {
                    if(antip->suspended_threads[i].id == rem_worker_id)
                        ResumeThread(antip->suspended_threads[i].handle);
                }

                antip->started = true;

                // Remove the breakpoint from the main thread and let it run
                SIZE_T written_bytes = 0;
                if (WriteProcessMemory(antip->process_info.hProcess,
                    (LPVOID)antip->entry_point, &antip->first_byte, 1, &written_bytes))
                {
                    //ResumeThread(antip->process_info.hThread);
                }
                break;
            }
            klen = hpa_parse_keyword(&at, "AntiPessimizerReady");
            if (klen > 0)
            {
                antip->running = true;

                // Can free every thread to run
                if (antip->suspended_threads)
                {
                    for (int i = 0; i < array_length(antip->suspended_threads); ++i)
                        ResumeThread(antip->suspended_threads[i].handle);
                    array_clear(antip->suspended_threads);
                }

                printf("Releasing all threads to run!\n");
                break;
            }

            klen = hpa_parse_keyword(&at, "AntiPessimizerPipeReady");
            if (klen > 0)
            {
                send_procedures_request(antip);
            }

            klen = hpa_parse_keyword(&at, "AntipessimizerInitProfilingTable");
            if (klen > 0)
            {
                hpa_parse_whitespace(&at);
                hpa_parse_keyword(&at, "ThreadTranslate=");
                antip->remote_thread_translate = (TThrTranslate*)hpa_parse_uint64_hex(&at);
                at++;
                antip->remote_thread_translate_size = hpa_parse_int32(&at);

                hpa_parse_whitespace(&at);
                hpa_parse_keyword(&at, "ProfileStack=");
                antip->remote_profile_stack = (void*)hpa_parse_uint64_hex(&at);
                at++;
                antip->remote_profile_stack_size = hpa_parse_int32(&at);
            }
        } break;
        case EXIT_PROCESS_DEBUG_EVENT: {
            printf("Process terminated with exit code %x\n", dbg_event.u.ExitProcess.dwExitCode);
            antip->debugging = false;
        } break;
        case RIP_EVENT:
            printf("dbg_event %d\n", dbg_event.dwDebugEventCode);
            break;
        case LOAD_DLL_DEBUG_EVENT: {
            wchar_t image_name[MAX_PATH];
            GetFinalPathNameByHandleW(dbg_event.u.LoadDll.hFile, image_name, MAX_PATH, FILE_NAME_NORMALIZED);
            printf("Loaded dll at %p %S\n", dbg_event.u.LoadDll.lpBaseOfDll, image_name);

            if (!antip->loaded_necessary_inject_dlls)
            {
                void* loadlibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "LoadLibraryA");
                void* sleeplibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "Sleep");
                if (loadlibaddr && sleeplibaddr)
                {
                    antip->loadlibaddr = loadlibaddr;
                    antip->sleeplibaddr = sleeplibaddr;
                    antip->loaded_necessary_inject_dlls = true;
                    injectcode(antip);
                    printf("- LoadLibraryA Address=%p\n", loadlibaddr);
                    printf("- Sleep Address=%p\n", sleeplibaddr);
                }
            }
        } break;
        default: break;
    }

    ContinueDebugEvent(dbg_event.dwProcessId,
        dbg_event.dwThreadId,
        dwContinueStatus);
}

static DWORD WINAPI 
antipessimizer_debug_thread(LPVOID param)
{
    const char* filepath = (const char*)param;

    antip.startup_info.cb = sizeof(STARTUPINFOA);

    BOOL proc_created = CreateProcessA(filepath, 0, 0, 0, FALSE, DEBUG_ONLY_THIS_PROCESS,
        0, 0, &antip.startup_info, &antip.process_info);

    antip.suspended_threads = array_new(RemoteThread);
    antip.remote_threads = array_new(RemoteThread);

    while (true)
    {
        DEBUG_EVENT dbg_event = { 0 };

        if (WaitForDebugEvent(&dbg_event, 100))
        {
            antipessimizer_process_next_debug_event(&antip, dbg_event);
        }

        if (!antip.debugging)
        {
            break;
        }
    }

    antipessimizer_stop();

    return 0;
}

int
antipessimizer_load_exe(const char* filepath, String* preselected)
{
    if (antip.debugging)
    {
        TerminateThread(antip.debugged_thread, 0);
        antipessimizer_stop();
        CloseHandle(antip.pipe);
    }

    antip.pipe = CreateNamedPipeA("\\\\.\\pipe\\AntiPessimizerPipe", PIPE_ACCESS_DUPLEX, PIPE_NOWAIT, PIPE_UNLIMITED_INSTANCES,
        64 * MEGABYTE, 64 * MEGABYTE, 0, 0);
    if (antip.pipe == INVALID_HANDLE_VALUE)
        return -1;
    antip.debugging = true;
    antip.debugged_thread = CreateThread(0, 0, antipessimizer_debug_thread, (LPVOID)filepath, 0, &antip.dbg_thread_id);
    if (antip.debugged_thread == INVALID_HANDLE_VALUE)
        return -1;

    antip.preselected_units = preselected;

    return 0;
}

int
antipessimizer_stop()
{
    TerminateProcess(antip.process_info.hProcess, 0);

    antip.loaded_necessary_inject_dlls = false;
    antip.started = false;
    antip.running = false;
    antip.debugging = false;

    array_clear(antip.remote_threads);
    array_clear(antip.suspended_threads);

    // Delete pipe?
    antip.remote_thread_id = 0;
    antip.loadlibaddr = 0;
    antip.sleeplibaddr = 0;

    antip.dbg_thread_id = 0;

    antip.should_clear = true;

    return 0;
}

void
antipessimizer_save_modules_selected()
{
    ModuleTable* modtable = &antip.module_table;
    if (modtable->modules && array_length(modtable->modules) > 0)
    {
        FILE* config = fopen("antipessimizer.modules", "wb");
        fprintf(config, "SelectedModules: [");


        for (int i = 0; i < array_length(modtable->modules); ++i)
        {
            ExeModule* em = modtable->modules + i;

            bool selected = em->flags & EXE_MODULE_SELECTED;
            if (selected)
            {
                fprintf(config, "%.*s,", (uint32_t)em->name.length, em->name.data);
            }
        }
        fprintf(config, "]");
        fclose(config);
    }
}

void
antipessimizer_clear()
{
    if (antip.should_clear)
    {
        antip.should_clear = false;

        if (antip.module_table.modules)
        {
            antipessimizer_save_modules_selected();

            for (int i = 0; i < array_length(antip.module_table.modules); ++i)
            {
                if (antip.module_table.modules[i].procedures)
                    array_free(antip.module_table.modules[i].procedures);
            }
            array_clear(antip.module_table.modules);
        }
    }
}

void
antipessimizer_clear_anchors()
{
    if (antip.prof_results.anchors)
        array_clear(antip.prof_results.anchors);
}

int
write_7bit_encoded_int(int value, char* buffer)
{
    char* start = buffer;
    do {
        if (value > 0x7f)
            *buffer = ((uint8_t)(value & 0x7f)) | 0x80;
        else
            *buffer = (uint8_t)value;
        value = value >> 7;
        buffer++;
    } while (value);
    return (int)(buffer - start);
}

int
read_7bit_encoded_int(unsigned char** data)
{
    unsigned char* at = (unsigned char*)(*data);
    int shift = 0;
    int value = 0;
    int result = 0;
    do {
        value = *at++;
        result = result | ((value & 0x7f) << shift);
        shift += 7;
    } while ((value & 0x80) != 0);

    (*data) = at;
    return result;
}

void
antipessimizer_init()
{
    if (antip.module_table.modules == 0)    
        antip.module_table.modules = array_new(ExeModule);
    if (antip.send_buffer == 0)
        antip.send_buffer = calloc(64, MEGABYTE);
    if (antip.recv_buffer == 0)
        antip.recv_buffer = arena_create(64 * MEGABYTE);

    antip.logbuffer = alloc_circular_buffer(1024 * 32, 3);
    antip.logbuffer.data = antip.logbuffer.base + antip.logbuffer.count;
    antip.logbuffer.at = antip.logbuffer.data;
}

int
antipessimizer_clear_results()
{
    if (!(antip.started && antip.running))
        return 0;

    // Suspend all threads but the worker thread so we can clear everything
    for (int i = 0; i < array_length(antip.remote_threads); ++i)
    {
        if (antip.remote_worker_id == antip.remote_threads[i].id)
            continue;
        RemoteThread rt = { antip.remote_threads[i].handle, antip.remote_threads[i].id };
        SuspendThread(antip.remote_threads[i].handle);
        array_push(antip.suspended_threads, rt);
    }

    DWORD written = 0;
    DebugRequest dr = { sizeof(DebugRequest) - sizeof(uint32_t), ctClearResults };
    WriteFile(antip.pipe, &dr, sizeof(dr), &written, 0);
}

typedef struct {
    int64_t count;
    int64_t cycle_count;
} AntipFileHeader;

void
antipessimizer_save_results()
{
    ProfilingResults* prof = antipessimizer_get_profiling_results();

    if (!prof->anchors)
        return;

    Light_Arena* str_arena = arena_create(MEGABYTE);
    char* str_arena_start = (char*)str_arena->ptr;

    ProfileAnchor* anchors = array_new(ProfileAnchor);

    for (int i = 0; i < array_length(prof->anchors); ++i)
    {
        ProfileAnchor* anchor = prof->anchors + i;

        int64_t* len = (int64_t*)arena_alloc(str_arena, sizeof(anchor->name.length));
        *len = anchor->name.length;

        char* name = (char*)arena_alloc(str_arena, anchor->name.length);
        memcpy(name, anchor->name.data, anchor->name.length);

        ProfileAnchor copy = *anchor;
        copy.name.data = (char*)(name - str_arena_start);

        array_push(anchors, copy);
    }

    OS_Datetime systime = { 0 };
    os_datetime(&systime);
    char filename[256] = { 0 };
    sprintf(filename, "%04d_%02d_%02d_%02d_%02d_%02d_run.antipessimizer",
        systime.year,
        systime.month,
        systime.day,
        systime.hour,
        systime.minute,
        systime.second);

    AntipFileHeader header = {
        array_length(anchors),
        prof->cycles_per_second
    };

    os_file_write(filename, &header, sizeof(header));
    
    os_file_append(filename, anchors, array_length(anchors) * sizeof(*anchors));
    os_file_append(filename, str_arena_start, (char*)str_arena->ptr - str_arena_start);

    arena_free(str_arena);
    array_free(anchors);
}

void
antipessimizer_load_results(const char* filename)
{
    ProfilingResults* prof = antipessimizer_get_profiling_results();

    int64_t filesize = 0;
    void* data = os_file_read(filename, &filesize);

    if (!data)
        return;

    if (!prof->anchors)
        prof->anchors = array_new(ProfileAnchor);
    
    array_clear(prof->anchors);

    char* at = (char*)data;

    int64_t count = *(int64_t*)at;
    at += sizeof(int64_t);
    prof->cycles_per_second = *(uint64_t*)at;
    at += sizeof(uint64_t);

    array_allocate(prof->anchors, count);
    array_length(prof->anchors) = count;
    memcpy(prof->anchors, at, count * sizeof(ProfileAnchor));    
    at += count * sizeof(ProfileAnchor);

    for (int64_t i = 0; i < count; ++i)
    {
        int64_t len = *(int64_t*)at;
        at += sizeof(int64_t);
        String name = ustr_new_len_c((char*)at, len);
        at += len;
        prof->anchors[i].name = name;
    }
}

int
antipessimizer_start(const char* filepath)
{
    if (antip.started && antip.running)
        return 0;

    char* at = (char*)antip.send_buffer;
    uint32_t* size = (uint32_t*)at;
    at += sizeof(uint32_t);
    *(int*)at = ctInstrumetProcedures;
    at += sizeof(int);

    if (antip.module_table.modules)
    {
        InstrumentedProcedure* instrumented = array_new(InstrumentedProcedure);
        for (int i = 0; i < array_length(antip.module_table.modules); ++i)
        {
            ExeModule* em = antip.module_table.modules + i;
            if (em->flags & EXE_MODULE_SELECTED && em->procedures)
            {
                for (int k = array_length(em->procedures) - 1; k >= 0; --k)
                {
                    InstrumentedProcedure* ip = em->procedures + k;
                    if (!string_has_prefix_char((char*)"System.", ip->demangled_name) &&
                        !string_has_prefix_char((char*)"Winapi.", ip->demangled_name) &&
                        !string_has_prefix_char((char*)"Jcl", ip->demangled_name))
                    {
                        array_push(instrumented, em->procedures[k]);
                    }
                    else
                    {
                        array_remove(em->procedures, k);
                    }
                }
            }
        }

        int proc_count = array_length(instrumented);

        *(int*)at = proc_count;
        at += sizeof(int);

        for (int k = proc_count - 1; k >= 0; --k)
        {
            InstrumentedProcedure* ip = instrumented + k;
            int len = write_7bit_encoded_int(ip->name.length, at);
            at += len;

            memcpy(at, ip->name.data, ip->name.length);
            at += ip->name.length;
        }
        array_free(instrumented);

        *size = (uint32_t)(at - antip.send_buffer - sizeof(uint32_t));

        DWORD written = 0;
        WriteFile(antip.pipe, antip.send_buffer, at - antip.send_buffer, &written, 0);
        printf("Sent %d bytes to pipe\n", *size);
    }

    return 0;
}

static int
compare_modules(const void* left, const void* right)
{
    ExeModule* l = (ExeModule*)left;
    ExeModule* r = (ExeModule*)right;

    return strcmp(l->name.data, r->name.data);
}

static void
sort_modules(ExeModule* modules)
{
    qsort(modules, array_length(modules), sizeof(*modules), compare_modules);
}

void
process_modules_message(uint8_t* msg, int size)
{
    int read_bytes = size;
    uint8_t* at = msg;
    while (read_bytes > 0)
    {
        uint8_t* start = at;
        int value = read_7bit_encoded_int(&at);
        String module_name = ustr_new_len_c((char*)at, value);
        at += value;

        int proc_count = *(int*)at;
        at += sizeof(int);

        ExeModule em = { module_name, proc_count };

        if (proc_count > 0)
            em.procedures = array_new(InstrumentedProcedure);

        for (int i = 0; i < proc_count; ++i)
        {
            value = read_7bit_encoded_int(&at);
            String proc = ustr_new_len_c((char*)at, value);
            at += value;

            value = read_7bit_encoded_int(&at);
            String demangled = ustr_new_len_c((char*)at, value);
            at += value;

            InstrumentedProcedure iproc = { proc, demangled };

            iproc.offset = *(uint32_t*)at;
            at += sizeof(uint32_t);
            iproc.size = *(uint32_t*)at;
            at += sizeof(uint32_t);

            array_push(em.procedures, iproc);
        }

        array_push(antip.module_table.modules, em);

        read_bytes -= (at - start);
    }

    sort_modules(antip.module_table.modules);

    if (antip.preselected_units && array_length(antip.preselected_units) > 0)
    {
        for (int k = 0; k < array_length(antip.preselected_units); ++k)
        {
            for (int i = 0; i < array_length(antip.module_table.modules); ++i)
            {
                ExeModule* em = antip.module_table.modules + i;

                if (string_equal(em->name, antip.preselected_units[k]))
                {
                    em->flags |= EXE_MODULE_SELECTED;
                }
            }
        }
        array_free(antip.preselected_units);
        antip.preselected_units = 0;
    }
}

void
process_profiling_result(uint8_t* msg, int size, bool has_name)
{
#if 0
    // Don't accept results after the process has terminated
    if (antip.debugging == false)
        return;
#endif

    if (antip.prof_results.anchors == 0)
    {
        antip.prof_results.anchors = array_new(ProfileAnchor);
    }

    array_clear(antip.prof_results.anchors);

    int read_bytes = size;
    uint8_t* at = msg;
    while (read_bytes > 0)
    {
        uint8_t* start = at;

        uint32_t count = *(uint32_t*)at;
        at += sizeof(uint32_t);

        antip.prof_results.cycles_per_second = *(uint64_t*)at;
        at += sizeof(uint64_t);

        for (uint32_t i = 0; i < count; ++i)
        {
            ProfileAnchor anchor;

            if (has_name)
            {
                int value = read_7bit_encoded_int(&at);
                if (value > 4096)
                {
                    goto cannot_read;
                }
                anchor.name = ustr_new_len_c((char*)at, value);
                at += value;
            }
            else
            {
                anchor.name.data = 0;
                anchor.name.length = 0;
            }

            anchor.address = *(uint64_t*)at;
            at += sizeof(uint64_t);
            anchor.thread_id = *(uint32_t*)at;
            at += sizeof(uint32_t);
            anchor.elapsed_exclusive = *(uint64_t*)at;
            at += sizeof(uint64_t);
            anchor.elapsed_inclusive = *(uint64_t*)at;
            at += sizeof(uint64_t);
            anchor.hitcount = *(uint64_t*)at;
            at += sizeof(uint64_t);

            if((int64_t)anchor.elapsed_exclusive > 0 && (int64_t)anchor.elapsed_inclusive > 0)
                array_push(antip.prof_results.anchors, anchor);
        }

        read_bytes -= (at - start);
    }
cannot_read:
    return;
}

String
antipessimizer_get_thread_name(uint32_t id)
{
    if (antip.remote_threads)
    {
        for (int i = 0; i < array_length(antip.remote_threads); ++i)
        {
            if (antip.remote_threads[i].id == id)
            {
                return antip.remote_threads[i].debug_name;
            }
        }
    }
    return {};
}

void*
antipessimizer_read_pipe_message()
{
    antipessimizer_clear();

    DWORD read_bytes = 0;    
    uint32_t size_to_read = 0;
    uint32_t msg_size = 0;

    while (ReadFile(antip.pipe, &size_to_read, sizeof(uint32_t), &read_bytes, 0))
    {
        msg_size = size_to_read;
        
        uint8_t* buffer = (uint8_t*)arena_alloc(antip.recv_buffer, size_to_read);
        uint8_t* at = buffer;
        while (size_to_read > 0)
        {
            ReadFile(antip.pipe, at, size_to_read, &read_bytes, 0);
            size_to_read -= read_bytes;
            at += read_bytes;

            // TODO(psv): This is not right
            if (read_bytes == 0)
            {
                break;
            }
        }

        uint32_t type = *(uint32_t*)buffer;
        switch (type)
        {
            case ctRequestProcedures: {
                process_modules_message(buffer + sizeof(type), msg_size - sizeof(type));
            } break;
            case ctProfilingData: {
                process_profiling_result(buffer + sizeof(type), msg_size - sizeof(type), true);
            } break;
            case ctProfilingDataNoName: {
                process_profiling_result(buffer + sizeof(type), msg_size - sizeof(type), false);
            } break;
            default: break;
        }

        arena_clear(antip.recv_buffer);
    }

    return &antip;
}

ProfilingResults*
antipessimizer_get_profiling_results()
{
    return &antip.prof_results;
}

ModuleTable* 
antipessimizer_get_module_table()
{
    return &antip.module_table;
}
