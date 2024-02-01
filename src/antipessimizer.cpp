#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <tchar.h>
#include <stdio.h>
#include <psapi.h>
#include <stdint.h>

#include <light_array.h>
#define HPA_IMPLEMENTATION
#include <hpa.h>

extern "C" {
#define UNICODE_CONVERT_IMPLEMENTATION
#include "unicode.h"
#include "string_utils.h"
}

#include "antipessimizer.h"

#define MEGABYTE (1024*1024)

struct Antipessimizer {
    bool loaded_necessary_inject_dlls = false;
    bool started = false;
    bool running = false;

    HANDLE debugged_thread;
    STARTUPINFOA startup_info = { 0 };
    PROCESS_INFORMATION process_info = { 0 };

    uint8_t first_byte = 0;
    DWORD64 entry_point = 0;

    HANDLE* suspended_threads;

    HANDLE pipe = 0;

    DWORD remote_thread_id = 0;

    void* loadlibaddr = 0;
    void* sleeplibaddr = 0;

    DWORD dbg_thread_id = 0;
};

static Antipessimizer antip;

void read_pipe_message();

void injectcode(Antipessimizer* antip)
{
    HANDLE process = antip->process_info.hProcess;

    void* base = VirtualAllocEx(process, 0, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (base)
    {
        char antip_path[MAX_PATH] = { 0 };
        DWORD namelen = GetFullPathNameA(".\\Win64\\Debug\\AntiPessimizerDLL.dll", sizeof(antip_path), antip_path, 0);

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

void
antipessimizer_process_next_debug_event(Antipessimizer* antip, DEBUG_EVENT& dbg_event)
{
    DWORD dwContinueStatus = DBG_CONTINUE;

    switch (dbg_event.dwDebugEventCode)
    {
        case EXCEPTION_DEBUG_EVENT: {
            switch (dbg_event.u.Exception.ExceptionRecord.ExceptionCode)
            {
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
                            SuspendThread(antip->process_info.hThread);
                            array_push(antip->suspended_threads, antip->process_info.hThread);
                        }
                    }
                }
            } break;
            case EXCEPTION_ACCESS_VIOLATION: {
                dwContinueStatus = DBG_EXCEPTION_NOT_HANDLED;

                DWORD tid = GetThreadId(antip->process_info.hThread);

                CONTEXT thctx = { 0 };
                thctx.ContextFlags = CONTEXT_ALL;
                if (GetThreadContext(antip->process_info.hThread, &thctx))
                {
                    char bytes[64] = { 0 };
                    SIZE_T read_bytes = 0;
                    if (ReadProcessMemory(antip->process_info.hProcess,
                        dbg_event.u.Exception.ExceptionRecord.ExceptionAddress, bytes, sizeof(bytes), &read_bytes))
                    {
                        int x = 0;
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
                array_push(antip->suspended_threads, dbg_event.u.CreateThread.hThread);
                SuspendThread(dbg_event.u.CreateThread.hThread);
            }
        } break;
        case CREATE_PROCESS_DEBUG_EVENT: {
            printf("Created process base %p Thread %d\n", dbg_event.u.CreateProcessInfo.lpBaseOfImage, dbg_event.dwThreadId);

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
            char buffer[1024] = { 0 };
            ReadProcessMemory(antip->process_info.hProcess,
                dbg_event.u.DebugString.lpDebugStringData, buffer, dbg_event.u.DebugString.nDebugStringLength, &bytesread);
            printf("%.*s\n", (int)bytesread, buffer);

            const char* at = buffer;
            int klen = hpa_parse_keyword(&at, "AntiPessimizerStartup");
            if (klen > 0)
            {
                hpa_parse_whitespace(&at);
                int rem_worker_id = hpa_parse_int32(&at);

                antip->started = true;

                // Remove the breakpoint from the main thread and let it run
                SIZE_T written_bytes = 0;
                if (WriteProcessMemory(antip->process_info.hProcess,
                    (LPVOID)antip->entry_point, &antip->first_byte, 1, &written_bytes))
                {
                    //ResumeThread(antip->process_info.hThread);
                }

#if 0
                // Can free every thread to run
                for (int i = 0; i < array_length(antip->suspended_threads); ++i)
                    ResumeThread(antip->suspended_threads[i]);
                array_clear(antip->suspended_threads);

                printf("Releasing all threads to run!\n");
#endif
            }
        } break;
        case EXIT_PROCESS_DEBUG_EVENT: {
            printf("Process terminated with exit code %x\n", dbg_event.u.ExitProcess.dwExitCode);
            //ExitProcess(0);
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

    BOOL proc_created = CreateProcessA(filepath, 0, 0, 0, FALSE, DEBUG_PROCESS,
        0, 0, &antip.startup_info, &antip.process_info);

    antip.suspended_threads = array_new(HANDLE);

    while (true)
    {
        DEBUG_EVENT dbg_event = { 0 };

        if (WaitForDebugEvent(&dbg_event, INFINITE))
        {
            antipessimizer_process_next_debug_event(&antip, dbg_event);
        }
    }

    TerminateProcess(antip.process_info.hProcess, 0);
}

int 
antipessimizer_start(const char* filepath)
{
    antip.running = true;

    // Can free every thread to run
    if (antip.suspended_threads)
    {
        for (int i = 0; i < array_length(antip.suspended_threads); ++i)
            ResumeThread(antip.suspended_threads[i]);
        array_clear(antip.suspended_threads);
    }

    printf("Releasing all threads to run!\n");
    return 0;
}

int
antipessimizer_load_exe(const char* filepath)
{
    antip.pipe = CreateNamedPipeA("\\\\.\\pipe\\AntiPessimizerPipe", PIPE_ACCESS_DUPLEX, PIPE_NOWAIT, PIPE_UNLIMITED_INSTANCES,
        MEGABYTE, MEGABYTE, 0, 0);
    if (antip.pipe == INVALID_HANDLE_VALUE)
        return -1;
    antip.debugged_thread = CreateThread(0, 0, antipessimizer_debug_thread, (LPVOID)filepath, 0, &antip.dbg_thread_id);
    if (antip.debugged_thread == INVALID_HANDLE_VALUE)
        return -1;
    return 0;
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

static uint8_t buffer[1024 * 1024];
extern Table g_module_table = {};

void
read_pipe_message()
{
    DWORD read_bytes = 0;

    if (g_module_table.modules == 0)
    {
        g_module_table.modules = array_new(ExeModule);
    }
    
    int bytes_to_read = 1024 * 1024;
    ReadFile(antip.pipe, buffer, bytes_to_read, &read_bytes, 0);

    uint8_t* at = buffer;
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
            em.procedures = array_new(String);

        for (int i = 0; i < proc_count; ++i)
        {
            value = read_7bit_encoded_int(&at);
            String proc = ustr_new_len_c((char*)at, value);
            at += value;
            array_push(em.procedures, proc);

            printf("Procedure %d: %s\n", i, proc.data);
        }
        
        array_push(g_module_table.modules, em);

        read_bytes -= (at - start);
    }
}