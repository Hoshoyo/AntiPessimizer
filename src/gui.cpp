#include "gui.h"
#include "antipessimizer.h"

#include <imgui.h>
#include <stdint.h>
#include <light_array.h>

static void text_label_left(const char* const label, char* buffer, int size, int align)
{
    float width = ImGui::CalcItemWidth();

    float x = ImGui::GetCursorPosX();
    ImGui::Text(label);
    ImGui::SameLine();
    ImGui::SetCursorPosX(align);
    ImGui::SetNextItemWidth(-1);

    ImGui::InputText(label, buffer, size);
}

void
gui_selection_window()
{
    read_pipe_message();
    //static char process_filepath[MAX_PATH] = "C:\\dev\\delphi\\GdiExample\\Win64\\Debug\\GdiExample.exe";
    static char process_filepath[MAX_PATH] = "C:\\Users\\T-GAMER\\Desktop\\temp\\KoTWithTD32\\KoT.PROFIT_64";
    //static char filter[128] = "LanguageEditorForm";
    static char filter[128] = "";
    static int last_selected = -1;
    static bool rt_results;

    if (ImGui::Begin("Project"))
    {
        if (ImGui::Button("Browse..."))
        {
            antipessimizer_stop();
        }
        ImGui::SameLine();
        if (ImGui::Button("Load Executable") && file_exists(process_filepath))
        {
            antipessimizer_load_exe(process_filepath);
        }
        ImGui::SameLine();
        if (ImGui::Button("Run") && file_exists(process_filepath))
        {
            antipessimizer_start(process_filepath);
        }
        ImGui::SameLine();
        if (ImGui::Button("Result"))
        {
            antipessimizer_request_result();
            rt_results = !rt_results;
        }

        //if (rt_results)
        antipessimizer_request_result();

        ImGui::Separator();
        int align_browse = 80.0f;
        text_label_left("Filepath", process_filepath, sizeof(process_filepath), align_browse);
        text_label_left("Filter", filter, sizeof(filter), align_browse);

        if (ImGui::BeginTable("split1", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_Borders))
        {
            if (g_module_table.modules)
            {
                for (int i = 0; i < array_length(g_module_table.modules); ++i)
                {
                    ExeModule* em = g_module_table.modules + i;

                    if (!strstr(em->name.data, filter))
                    {
                        continue;
                    }

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
    }
    ImGui::End();

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
                        //ImGui::Text("%s (%x:%x)", procs[i].name.data, procs[i].offset, procs[i].size);
                    }
                }
            }
            ImGui::EndTable();
        }
    }
    ImGui::End();
}

typedef enum {
    RESULT_COL_NAME,
    RESULT_COL_ELAPSED_INCLUSIVE,
    RESULT_COL_ELAPSED_EXCLUSIVE,
    RESULT_COL_HITCOUNT,
    RESULT_COL_THREAD_ID,
} Result_ColumnID;

static int sort_algo_direction = 1;

static int
compare_anchor_hitcount(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;

    int result = left->hitcount - right->hitcount;
    if (result == 0)
        result = strncmp(left->name.data, right->name.data, left->name.length);
    return result * sort_algo_direction;
}

static int
compare_anchor_name(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;    
    return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

static int
compare_anchor_elapsed_inclusive(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;
    int64_t res = (int64_t)left->elapsed_inclusive - (int64_t)right->elapsed_inclusive;
    int sign = (int)(-((int64_t)(((uint64_t)res >> 63) * 2) - 1));

    if (res != 0)
        return sort_algo_direction * sign;
    else
        return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

static int
compare_anchor_elapsed_exclusive(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;
    int64_t res = (int64_t)left->elapsed_exclusive - (int64_t)right->elapsed_exclusive;
    int sign = (int)(-((int64_t)(((uint64_t)res >> 63) * 2) - 1));

    if (res != 0)
        return sort_algo_direction * sign;
    else
        return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

typedef int sort_algo_t(const void*, const void*);
static sort_algo_t* sort_algorithms[] = {
    compare_anchor_name,
    compare_anchor_elapsed_inclusive,
    compare_anchor_elapsed_exclusive,
    compare_anchor_hitcount,
};

void
gui_results()
{
    ProfilingResults* prof = antipessimizer_get_profiling_results();

    const float TEXT_BASE_HEIGHT = ImGui::GetTextLineHeightWithSpacing();
    static ImGuiTableFlags flags =
        ImGuiTableFlags_Resizable | ImGuiTableFlags_Reorderable | ImGuiTableFlags_Hideable | ImGuiTableFlags_Sortable | ImGuiTableFlags_SortMulti
        | ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersOuter | ImGuiTableFlags_BordersV | ImGuiTableFlags_NoBordersInBody
        | ImGuiTableFlags_ScrollY;

    if (ImGui::Begin("Results Sorted"))
    {
        if (ImGui::BeginTable("table_sorting", 5, flags))
        {
            ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_NAME);
            ImGui::TableSetupColumn("Elapsed exclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_ELAPSED_EXCLUSIVE);
            ImGui::TableSetupColumn("Elapsed inclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_ELAPSED_INCLUSIVE);
            ImGui::TableSetupColumn("Hit count", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_HITCOUNT);
            ImGui::TableSetupColumn("Thread ID", ImGuiTableColumnFlags_NoSort, 0.0f, RESULT_COL_THREAD_ID);
            ImGui::TableSetupScrollFreeze(0, 1); // Make row always visible
            ImGui::TableHeadersRow();

            ImGuiTableSortSpecs* sort_specs = ImGui::TableGetSortSpecs();

            uint64_t cycles_per_sec = prof->cycles_per_second;

            if (prof->anchors)
            {
                if (sort_specs->SpecsCount > 0)
                {
                    if (sort_specs->Specs[0].SortDirection == 1)
                        sort_algo_direction = 1;
                    else
                        sort_algo_direction = -1;
                    qsort(prof->anchors, (size_t)array_length(prof->anchors), sizeof(prof->anchors[0]), sort_algorithms[sort_specs->Specs[0].ColumnUserID]);
                }

                ImGuiListClipper clipper;
                clipper.Begin(array_length(prof->anchors));
                while (clipper.Step())
                {
                    for (int row_n = clipper.DisplayStart; row_n < clipper.DisplayEnd; row_n++)
                    {
                        ProfileAnchor* item = &prof->anchors[row_n];
                        ImGui::PushID(item->name.data);
                        ImGui::TableNextRow();
                        ImGui::TableNextColumn();
                        ImGui::Text("%s", item->name.data);
                        ImGui::TableNextColumn();
                        ImGui::Text("%.4f", cycles_to_ms(prof->anchors[row_n].elapsed_exclusive, cycles_per_sec));
                        ImGui::TableNextColumn();
                        ImGui::Text("%.4f", cycles_to_ms(prof->anchors[row_n].elapsed_inclusive, cycles_per_sec));
                        ImGui::TableNextColumn();
                        ImGui::Text("%lld", item->hitcount);
                        ImGui::TableNextColumn();
                        String thread_name = antipessimizer_get_thread_name(item->thread_id);
                        if(thread_name.length > 0)
                            ImGui::Text("%s", thread_name.data);
                        else
                            ImGui::Text("%d", item->thread_id);
                        ImGui::PopID();
                    }
                }
            }
            ImGui::EndTable();
        }
    }
    ImGui::End();
}

void
gui_init()
{
    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;

    ImGui::StyleColorsDark();

    // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
    {
        style.WindowRounding = 0.0f;
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }
}

void 
gui_render()
{
    ImGui::NewFrame();
    ImGui::DockSpaceOverViewport(ImGui::GetMainViewport());

    {
        gui_selection_window();
        gui_results();
    }

    ImGui::Render();
}