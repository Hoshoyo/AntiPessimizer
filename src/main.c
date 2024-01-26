#include <windows.h>
#include <tchar.h>
#include <stdio.h>
#include <psapi.h>

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
    int loaded = 0;
    STARTUPINFOA startup_info = { 0 };
    startup_info.cb = sizeof(STARTUPINFOA);
    PROCESS_INFORMATION process_info = { 0 };
    const char* filepath = "C:\\dev\\delphi\\GdiExample\\Win64\\Debug\\GdiExample.exe";

    BOOL m = CreateProcessA(filepath, 0, 0, 0, FALSE, DEBUG_PROCESS,
        0, 0, &startup_info, &process_info);

    DWORD dwContinueStatus = DBG_CONTINUE;
    DEBUG_EVENT dbg_event = { 0 };
    while (1)
    {
        WaitForDebugEvent(&dbg_event, INFINITE);

        switch (dbg_event.dwDebugEventCode)
        {
            case EXCEPTION_DEBUG_EVENT:
            case CREATE_THREAD_DEBUG_EVENT: {
                if (dbg_event.dwThreadId != remote_thread_id)
                {
                    printf("Created Thread %d\n", dbg_event.dwThreadId);
                }
                else
                {
                    Sleep(100);
                }
            } break;
            case CREATE_PROCESS_DEBUG_EVENT: {
                printf("Created process base %p Thread %d\n", dbg_event.u.CreateProcessInfo.lpBaseOfImage, dbg_event.dwThreadId);
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
                int x = 0;
            } break;
            case EXIT_PROCESS_DEBUG_EVENT: {
                //ExitProcess(0);
            } break;
            case RIP_EVENT:
                printf("dbg_event %d\n", dbg_event.dwDebugEventCode);
                break;
            case LOAD_DLL_DEBUG_EVENT: {
                printf("Loaded dll at %p\n", dbg_event.u.LoadDll.lpBaseOfDll);

                if (!loaded)
                {
                    void* loadlibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "LoadLibraryA");
                    void* sleeplibaddr = GetProcAddress((HMODULE)dbg_event.u.LoadDll.lpBaseOfDll, "Sleep");
                    if (loadlibaddr && sleeplibaddr)
                    {
                        loaded = 1;
                        injectcode(process_info.hProcess, loadlibaddr, sleeplibaddr);
                        printf("######### LoadLibraryA Address=%p\n", loadlibaddr);
                        printf("######### Sleep Address=%p\n", sleeplibaddr);
                    }
                }
            } break;
            default: break;
        }
        ContinueDebugEvent(dbg_event.dwProcessId,
            dbg_event.dwThreadId,
            dwContinueStatus);
    }

    TerminateProcess(process_info.hProcess, 0);

    return 0;
}