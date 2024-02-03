#define _CRT_SECURE_NO_WARNINGS
#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include <d3d11.h>
#include <tchar.h>
#include <math.h>
#include <stdio.h>

extern "C" {
#include "string_utils.h"
#include <light_array.h>
}

#include "antipessimizer.h"

// Data
static ID3D11Device*            g_pd3dDevice = 0;
static ID3D11DeviceContext*     g_pd3dDeviceContext = 0;
static IDXGISwapChain*          g_pSwapChain = 0;
static UINT                     g_ResizeWidth = 0, g_ResizeHeight = 0;
static ID3D11RenderTargetView*  g_mainRenderTargetView = 0;

// Forward declarations of helper functions
bool CreateDeviceD3D(HWND hWnd);
void CleanupDeviceD3D();
void CreateRenderTarget();
void CleanupRenderTarget();
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

static double
cycles_to_ms(uint64_t cycles, uint64_t cycles_per_second)
{
    return ((double)cycles / (double)cycles_per_second) * 1000.0;
}

static void 
RenderResults()
{
    ProfilingResults* prof = antipessimizer_get_profiling_results();
    if (ImGui::Begin("Results"))
    {
#if 0
        ImDrawList* draw_list = ImGui::GetWindowDrawList();
        {
            ImVec2 p0 = ImGui::GetCursorScreenPos();
            draw_list->AddRectFilled(ImVec2(p0.x,p0.y), ImVec2(p0.x + 100, p0.y + 100), IM_COL32(0xff, 0xaa, 0xaa, 0xaa));
        }
#endif
        if (ImGui::BeginTable("table_results", 4, ImGuiTableFlags_Resizable | ImGuiTableFlags_Borders))
        {
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::Text("Procedure");
            ImGui::TableNextColumn();
            ImGui::Text("Exclusive");
            ImGui::TableNextColumn();
            ImGui::Text("With children");
            ImGui::TableNextColumn();
            ImGui::Text("Hit count");

            if (prof->anchors)
            {
                uint64_t cycles_per_sec = prof->cycles_per_second;
                for (int i = 0; i < array_length(prof->anchors); ++i)
                {
                    ImGui::TableNextRow();
                    ImGui::TableNextColumn();
                    ImGui::Text("%.*s", prof->anchors[i].name.length, prof->anchors[i].name.data);
                    ImGui::TableNextColumn();
                    ImGui::Text("%.4f ms", cycles_to_ms(prof->anchors[i].elapsed_exclusive, cycles_per_sec));
                    ImGui::TableNextColumn();
                    ImGui::Text("%.4f ms", cycles_to_ms(prof->anchors[i].elapsed_inclusive, cycles_per_sec));
                    ImGui::TableNextColumn();
                    ImGui::Text("%lld", prof->anchors[i].hitcount);
                }
            }

            ImGui::EndTable();
        }

        ImGui::End();
    }
}

BOOL file_exists(char* szPath)
{
    DWORD dwAttrib = GetFileAttributesA(szPath);

    return (dwAttrib != INVALID_FILE_ATTRIBUTES &&
        !(dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}

static void
SelectionWindow()
{
    read_pipe_message();
    static char process_filepath[MAX_PATH] = "C:\\dev\\delphi\\GdiExample\\Win64\\Debug\\GdiExample.exe";
    static int last_selected = -1;

    if (ImGui::Begin("Project"))
    {
        ImGui::Columns(4, 0, false);
        if (ImGui::Button("Browse..."))
        {
            antipessimizer_stop();            
        }
        ImGui::NextColumn();
        if (ImGui::Button("Load Executable") && file_exists(process_filepath))
        {
            antipessimizer_load_exe(process_filepath);
        }
        ImGui::NextColumn();
        if (ImGui::Button("Run") && file_exists(process_filepath))
        {
            antipessimizer_start(process_filepath);
        }
        ImGui::NextColumn();
        if (ImGui::Button("Result"))
        {
            antipessimizer_request_result();
        }
        antipessimizer_request_result();

        ImGui::Columns(1);
        ImGui::InputText("Filepath", process_filepath, sizeof(process_filepath));

        if (ImGui::BeginTable("split1", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_Borders))
        {
            if (g_module_table.modules)
            {
                for (int i = 0; i < array_length(g_module_table.modules); ++i)
                {
                    ExeModule* em = g_module_table.modules + i;

                    bool selected = em->flags & EXE_MODULE_SELECTED;
                    ImGui::TableNextRow();
                    ImGui::TableNextColumn();
                    if (ImGui::Selectable(em->name.data, &selected, ImGuiSelectableFlags_SpanAllColumns))
                        last_selected = i;
                    ImGui::TableNextColumn();
                    ImGui::Text("%d", em->proc_count);

                    if (selected)
                        em->flags |= EXE_MODULE_SELECTED;
                    else
                        em->flags &= ~(EXE_MODULE_SELECTED);
                }
            }
            ImGui::EndTable();
        }
        ImGui::End();
    }

    if (ImGui::Begin("Procedures"))
    {
        if (ImGui::BeginTable("split1", 1, ImGuiTableFlags_Resizable | ImGuiTableFlags_Borders))
        {
            if (g_module_table.modules != 0 && last_selected >= 0 && last_selected < array_length(g_module_table.modules))
            {
                ExeModule* em = g_module_table.modules + last_selected;
                InstrumentedProcedure* procs = em->procedures;
                if (procs)
                {
                    for (int i = 0; i < array_length(procs); ++i)
                    {
                        ImGui::TableNextRow();
                        ImGui::TableNextColumn();
                        ImGui::Text("%s", procs[i].demangled_name.data);
                    }
                }
            }
            ImGui::EndTable();
        }
        ImGui::End();
    }
}

int main(int, char**)
{
    // Create application window
    WNDCLASSEXW wc = { sizeof(wc), CS_CLASSDC, WndProc, 0, 0, GetModuleHandle(0), 0, 0, 0, 0, L"AntiPessimizerClass", 0 };
    RegisterClassExW(&wc);
    HWND hwnd = CreateWindowW(wc.lpszClassName, L"AntiPessimizer", WS_OVERLAPPEDWINDOW, 100, 100, 1280, 800, 0, 0, wc.hInstance, 0);

    // Initialize Direct3D
    if (!CreateDeviceD3D(hwnd))
    {
        CleanupDeviceD3D();
        UnregisterClassW(wc.lpszClassName, wc.hInstance);
        return 1;
    }

    // Show the window
    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);

    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking

    ImGui::StyleColorsDark();

    // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
    {
        style.WindowRounding = 0.0f;
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Setup Platform/Renderer backends
    ImGui_ImplWin32_Init(hwnd);
    ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

    ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

    wstring_init_globals();
    string_init_globals();

    // Main loop
    bool done = false;
    while (!done)
    {
        MSG msg;
        while (PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            if (msg.message == WM_QUIT)
                done = true;
        }
        if (done)
            break;

        // Handle window resize (we don't resize directly in the WM_SIZE handler)
        if (g_ResizeWidth != 0 && g_ResizeHeight != 0)
        {
            CleanupRenderTarget();
            g_pSwapChain->ResizeBuffers(0, g_ResizeWidth, g_ResizeHeight, DXGI_FORMAT_UNKNOWN, 0);
            g_ResizeWidth = g_ResizeHeight = 0;
            CreateRenderTarget();
        }

        // Start the Dear ImGui frame
        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();

        // Application rendering
        {
            ImGui::DockSpaceOverViewport(ImGui::GetMainViewport());
            RenderResults();
            SelectionWindow();
        }

        // Rendering
        ImGui::Render();
        const float clear_color_with_alpha[4] = { clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w };
        g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, nullptr);
        g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, clear_color_with_alpha);
        ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

        // Update and Render additional Platform Windows
        if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
        {
            ImGui::UpdatePlatformWindows();
            ImGui::RenderPlatformWindowsDefault();
        }

        g_pSwapChain->Present(1, 0); // Present with vsync
    }

    // Cleanup
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();

    CleanupDeviceD3D();
    DestroyWindow(hwnd);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);

    return 0;
}

// Helper functions
bool CreateDeviceD3D(HWND hWnd)
{
    // Setup swap chain
    DXGI_SWAP_CHAIN_DESC sd;
    ZeroMemory(&sd, sizeof(sd));
    sd.BufferCount = 2;
    sd.BufferDesc.Width = 0;
    sd.BufferDesc.Height = 0;
    sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = hWnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;

    UINT createDeviceFlags = 0;
    //createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
    D3D_FEATURE_LEVEL featureLevel;
    const D3D_FEATURE_LEVEL featureLevelArray[2] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0, };
    HRESULT res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);
    if (res == DXGI_ERROR_UNSUPPORTED) // Try high-performance WARP software driver if hardware is not available.
        res = D3D11CreateDeviceAndSwapChain(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, createDeviceFlags, featureLevelArray, 2, D3D11_SDK_VERSION, &sd, &g_pSwapChain, &g_pd3dDevice, &featureLevel, &g_pd3dDeviceContext);
    if (res != S_OK)
        return false;

    CreateRenderTarget();
    return true;
}

void CleanupDeviceD3D()
{
    CleanupRenderTarget();
    if (g_pSwapChain) { g_pSwapChain->Release(); g_pSwapChain = nullptr; }
    if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nullptr; }
    if (g_pd3dDevice) { g_pd3dDevice->Release(); g_pd3dDevice = nullptr; }
}

void CreateRenderTarget()
{
    ID3D11Texture2D* pBackBuffer;
    g_pSwapChain->GetBuffer(0, IID_PPV_ARGS(&pBackBuffer));
    g_pd3dDevice->CreateRenderTargetView(pBackBuffer, nullptr, &g_mainRenderTargetView);
    pBackBuffer->Release();
}

void CleanupRenderTarget()
{
    if (g_mainRenderTargetView) { g_mainRenderTargetView->Release(); g_mainRenderTargetView = nullptr; }
}

#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0 // From Windows SDK 8.1+ headers
#endif

// Forward declare message handler from imgui_impl_win32.cpp
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    switch (msg)
    {
    case WM_SIZE:
        if (wParam == SIZE_MINIMIZED)
            return 0;
        g_ResizeWidth = (UINT)LOWORD(lParam); // Queue resize
        g_ResizeHeight = (UINT)HIWORD(lParam);
        return 0;
    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU) // Disable ALT application menu
            return 0;
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    case WM_DPICHANGED:
        if (ImGui::GetIO().ConfigFlags & ImGuiConfigFlags_DpiEnableScaleViewports)
        {
            const RECT* suggested_rect = (RECT*)lParam;
            SetWindowPos(hWnd, nullptr, suggested_rect->left, suggested_rect->top, suggested_rect->right - suggested_rect->left, suggested_rect->bottom - suggested_rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
        }
        break;
    }
    return DefWindowProcW(hWnd, msg, wParam, lParam);
}