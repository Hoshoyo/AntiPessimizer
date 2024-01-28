#include <windows.h>
#include <tchar.h>
#include <stdio.h>
#include <psapi.h>
#include <stdint.h>

#include "light_array.h"

DWORD remote_thread_id = 0;

void injectcode(HANDLE process, void* loadlibaddr, void* sleeplibaddr)
{
    void* base = VirtualAllocEx(process, 0, 4096, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (base)
    {
        char path[] = "C:\\dev\\delphi\\AntiPessimizer\\Win64\\Debug\\AntiPessimizerDLL.dll";

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
        WriteProcessMemory(process, at, &loadlibaddr, sizeof(void*), &written);
        at += written;
        WriteProcessMemory(process, at, &sleeplibaddr, sizeof(void*), &written);
        at += written;
        WriteProcessMemory(process, at, path, sizeof(path), &written);
        at += written;

        HANDLE thread_handle = CreateRemoteThread(process, 0, 0, (DWORD(*)(LPVOID))base, (char*)base + 1024, 0, &remote_thread_id);
        printf("Created remote thread %d\n", remote_thread_id);
    }
    else
    {
        printf("Error allocating memory on process\n");
    }
}

int main(int argc, char** argv)
{
    int loaded_necessary_inject_dlls = 0;
    int antipessimizer_started = 0;
    STARTUPINFOA startup_info = { 0 };
    startup_info.cb = sizeof(STARTUPINFOA);
    PROCESS_INFORMATION process_info = { 0 };
    const char* filepath = "C:\\dev\\delphi\\GdiExample\\Win64\\Debug\\GdiExample.exe";

    BOOL m = CreateProcessA(filepath, 0, 0, 0, FALSE, DEBUG_PROCESS,
        0, 0, &startup_info, &process_info);

    uint8_t first_byte = 0;
    DWORD64 entry_point = 0;

    HANDLE* suspended_threads = array_new(HANDLE);

    DWORD dwContinueStatus = DBG_CONTINUE;
    DEBUG_EVENT dbg_event = { 0 };
    while (1)
    {
        dwContinueStatus = DBG_CONTINUE;

        if (!WaitForDebugEvent(&dbg_event, INFINITE))
        {
            continue;
        }

        switch (dbg_event.dwDebugEventCode)
        {
            case EXCEPTION_DEBUG_EVENT: {
                switch (dbg_event.u.Exception.ExceptionRecord.ExceptionCode)
                {
                    case EXCEPTION_BREAKPOINT: {
                        CONTEXT thctx = { 0 };
                        thctx.ContextFlags = CONTEXT_ALL;

                        if (GetThreadContext(process_info.hThread, &thctx))
                        {
                            if (thctx.Rip == (DWORD64)entry_point + 1)
                            {
                                thctx.Rip = thctx.Rip - 1;
                                SetThreadContext(process_info.hThread, &thctx);

                                if (!antipessimizer_started)
                                {
                                    SuspendThread(process_info.hThread);
                                }
                            }
                        }
                    } break;
                    case EXCEPTION_ACCESS_VIOLATION: {
                        dwContinueStatus = DBG_EXCEPTION_NOT_HANDLED;
#if 1
                        DWORD tid = GetThreadId(process_info.hThread);

                        CONTEXT thctx = { 0 };
                        thctx.ContextFlags = CONTEXT_ALL;
                        if (GetThreadContext(process_info.hThread, &thctx))
                        {
                            char bytes[64] = { 0 };
                            SIZE_T read_bytes = 0;
                            if (ReadProcessMemory(process_info.hProcess,
                                dbg_event.u.Exception.ExceptionRecord.ExceptionAddress, bytes, sizeof(bytes), &read_bytes))
                            {
                                int x = 0;
                            }
                        }
#endif
                    } break;
                    default: {
                        int x = 0;
                    }break;
                }
            } break;
            case CREATE_THREAD_DEBUG_EVENT: {
                printf("Created Thread %d\n", dbg_event.dwThreadId);
                if (dbg_event.dwThreadId == remote_thread_id)
                {
                    // this is the antipessimizer thread, let it run
                }
                else if(GetThreadId(dbg_event.u.CreateThread.hThread) == GetThreadId(process_info.hThread))
                {
                    // this is the main thread, let it run until it is stopped at the entry point
                }
                else if (!antipessimizer_started)
                {
                    // this is any other thread, just suspend until antipessimizer is ready
                    array_push(suspended_threads, dbg_event.u.CreateThread.hThread);
                    SuspendThread(dbg_event.u.CreateThread.hThread);
                }
            } break;
            case CREATE_PROCESS_DEBUG_EVENT: {
                printf("Created process base %p Thread %d\n", dbg_event.u.CreateProcessInfo.lpBaseOfImage, dbg_event.dwThreadId);
#if 1
                SuspendThread(dbg_event.u.CreateProcessInfo.hThread);
                entry_point = (DWORD64)dbg_event.u.CreateProcessInfo.lpStartAddress;
                
                SIZE_T read_bytes = 0;
                if (ReadProcessMemory(dbg_event.u.CreateProcessInfo.hProcess,
                    dbg_event.u.CreateProcessInfo.lpStartAddress, &first_byte, 1, &read_bytes))
                {
                    uint8_t int8 = 0xcc;
                    SIZE_T written_bytes = 0;
                    if (WriteProcessMemory(process_info.hProcess,
                        entry_point, &int8, 1, &written_bytes))
                    {
                        ResumeThread(dbg_event.u.CreateProcessInfo.hThread);
                    }
                }
#endif
            } break;
            case EXIT_THREAD_DEBUG_EVENT: {
                printf("Exit thread %d\n", dbg_event.dwThreadId);
            } break;
            case UNLOAD_DLL_DEBUG_EVENT:
                break;
            case OUTPUT_DEBUG_STRING_EVENT: {
                SIZE_T bytesread = 0;
                char buffer[1024] = { 0 };
                ReadProcessMemory(process_info.hProcess,
                    dbg_event.u.DebugString.lpDebugStringData, buffer, dbg_event.u.DebugString.nDebugStringLength, &bytesread);
                printf("%.*s\n", (int)bytesread, buffer);
#if 1
                if (strcmp(buffer, "AntiPessimizerStartup") == 0)
                {
                    antipessimizer_started = 1;

                    // Remove the breakpoint from the main thread and let it run
                    SIZE_T written_bytes = 0;
                    if (WriteProcessMemory(process_info.hProcess,
                        entry_point, &first_byte, 1, &written_bytes))
                    {
                        ResumeThread(process_info.hThread);
                    }

                    // Can free every thread to run
                    for (int i = 0; i < array_length(suspended_threads); ++i)
                        ResumeThread(suspended_threads[i]);
                    array_clear(suspended_threads);

                    printf("Releasing all threads to run!\n");
                }
#endif
            } break;
            case EXIT_PROCESS_DEBUG_EVENT: {
                //ExitProcess(0);
            } break;
            case RIP_EVENT:
                printf("dbg_event %d\n", dbg_event.dwDebugEventCode);
                break;
            case LOAD_DLL_DEBUG_EVENT: {
                wchar_t image_name[MAX_PATH];
                GetFinalPathNameByHandle(dbg_event.u.LoadDll.hFile, image_name, MAX_PATH, FILE_NAME_NORMALIZED);
                printf("Loaded dll at %p %S\n", dbg_event.u.LoadDll.lpBaseOfDll, image_name);

                if (!loaded_necessary_inject_dlls)
                {
                    void* loadlibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "LoadLibraryA");
                    void* sleeplibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "Sleep");
                    if (loadlibaddr && sleeplibaddr)
                    {
                        loaded_necessary_inject_dlls = 1;
                        injectcode(process_info.hProcess, loadlibaddr, sleeplibaddr);
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
        dwContinueStatus = DBG_CONTINUE;
    }

    TerminateProcess(process_info.hProcess, 0);

    return 0;
}