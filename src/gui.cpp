#define _CRT_SECURE_NO_WARNINGS
#include "gui.h"
#include "antipessimizer.h"

#include <imgui.h>
#include <stdint.h>
#include <light_array.h>
#include <hpa.h>

#include "colors.h"

#define CIRCULARBUFFER_IMPLEMENTATION
#include "log.h"

CircularBuffer* antipessimizer_get_logbuffer();

#define MILLISECOND (1000000.0f)
#define SWAP_FLOAT(x, y) { float temp = x; x = y; y = temp; }

static void text_label_left(const char* const label, char* buffer, int size, int align)
{
    ImGui::Text(label);
    ImGui::SameLine();
    ImGui::SetCursorPosX(align);
    ImGui::SetNextItemWidth(-1);
    ImGui::InputText(label, buffer, size);
}

static String
unmangle_name(String name)
{    
    if (name.length > 3 && name.data[0] == '_' && name.data[1] == 'Z' && name.data[2] == 'N')
    {
        String res = { 0 };
        const char* at = name.data + 3;
        while (at < name.data + name.length)
        {
            int32_t len = hpa_parse_int32(&at);
            if (len <= 0)
                break;
            if (res.length > 0)
                res = tmp_str_concat(res, tmp_str_new_c((char*)"."));
                        
            res = tmp_str_concat(res, tmp_str_new_len((char*)at, len));
            at += len;
        }
        return res;
    }
   
    return name;
}

void
gui_selection_window(Gui_State* gui)
{
    ModuleTable* modtable = antipessimizer_get_module_table();

    if (ImGui::Begin("Project"))
    {
        if (ImGui::Button("Browse..."))
        {
            os_browse_file(gui->process_filepath, sizeof(gui->process_filepath));
        }        
        ImGui::SameLine();
        if (ImGui::Button("Load Executable") && file_exists(gui->process_filepath))
        {
            antipessimizer_load_exe(gui->process_filepath, gui->loaded_units);
        }
        ImGui::SameLine();
        if (ImGui::Button("Run") && file_exists(gui->process_filepath))
        {
            // When running again, clear the old results
            // TODO(psv): Save results before clearing
            antipessimizer_clear_anchors();
            antipessimizer_start(gui->process_filepath);
            gui->realtime_results = true;
        }
        ImGui::SameLine();
        if (ImGui::Button("Save"))
        {
            antipessimizer_save_results();
        }
        ImGui::SameLine();
        if (ImGui::Button("Clear"))
        {
            antipessimizer_clear_results();
        }

        if (ImGui::Button("Realtime"))
        {
            gui->realtime_results = !gui->realtime_results;
        }
        if (!gui->realtime_results)
        {
            ImGui::SameLine();
            if (ImGui::Button("Result"))
            {
                antipessimizer_request_result();
            }
        }

        ImGui::SameLine();
        ImGui::SetNextItemWidth(100.0f);
        ImGui::DragInt("Cycle discount", (int*)&gui->fixed_cycle_discount, 1.0f, 0, 1000, "%d", ImGuiSliderFlags_None);

        if (gui->realtime_results)
            antipessimizer_request_result();

        ImGui::Separator();

        int align_browse = 80.0f;
        text_label_left("Filepath", gui->process_filepath, sizeof(gui->process_filepath), align_browse);
        text_label_left("Filter", gui->unit_filter, sizeof(gui->unit_filter), align_browse);
        if (modtable)
        {
            int64_t modules_selected = 0;
            int64_t procedure_count = 0;
            int64_t procedures_selected = 0;
            for (int i = 0; i < array_length(modtable->modules); ++i)
            {
                ExeModule* em = modtable->modules + i;
                procedure_count += em->proc_count;
                if (em->flags & EXE_MODULE_SELECTED)
                {
                    procedures_selected += em->proc_count;
                    modules_selected++;
                }
            }
            ImGui::Text("Modules Count:       %lld", array_length(modtable->modules));
            ImGui::Text("Modules Selected:    %lld", modules_selected);
            ImGui::Text("Procedures Count:    %lld", procedure_count);
            ImGui::Text("Procedures Selected: %lld", procedures_selected);
        }

        bool select_all_filtered = false;
        bool unselect_all_filtered = false;
        if (ImGui::Button("Select All Filtered"))
            select_all_filtered = true;
        ImGui::SameLine();
        if (ImGui::Button("Unselect All Filtered"))
            unselect_all_filtered = true;

        if (ImGui::BeginTable("split1", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_Borders))
        {
            if (modtable)
            {
                for (int i = 0; i < array_length(modtable->modules); ++i)
                {
                    ExeModule* em = modtable->modules + i;
                    
                    if (!strstr(tmp_str_lowercase(em->name).data, tmp_str_lowercase(tmp_str_new_c(gui->unit_filter)).data))
                    {                        
                        continue;
                    }

                    bool selected = em->flags & EXE_MODULE_SELECTED;
                    ImGui::TableNextRow();
                    ImGui::TableNextColumn();
                    if (ImGui::Selectable(em->name.data, &selected, ImGuiSelectableFlags_SpanAllColumns))
                        gui->procedure_last_selected = i;
                    ImGui::TableNextColumn();
                    ImGui::Text("%d", em->proc_count);
                    
                    if (selected)
                        em->flags |= EXE_MODULE_SELECTED;
                    else
                        em->flags &= ~(EXE_MODULE_SELECTED);

                    if (select_all_filtered)
                        em->flags |= EXE_MODULE_SELECTED;
                    if (unselect_all_filtered)
                        em->flags &= ~(EXE_MODULE_SELECTED);
                }
            }
            ImGui::EndTable();
        }
    }
    ImGui::End();

    // Log window
    CircularBuffer* lbuffer = antipessimizer_get_logbuffer();
    ImGui::Begin("Log");
    if (ImGui::Button("Copy to Clipboard"))
    {
        *lbuffer->at = 0;
        ImGui::SetClipboardText((const char*)lbuffer->data);
    }
    ImGui::BeginChild("##log", ImVec2(0.0f, 0.0f), ImGuiChildFlags_Border, ImGuiWindowFlags_AlwaysVerticalScrollbar | ImGuiWindowFlags_AlwaysHorizontalScrollbar);

    ImGuiListClipper clipper;
    clipper.Begin(1);
    while (clipper.Step())
    {
        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.4f, 0.4f, 1.0f));
        for (int line_no = clipper.DisplayStart; line_no < clipper.DisplayEnd; line_no++)
        {
            const char* test = (const char*)lbuffer->data;
            ImGui::TextUnformatted(test, (const char*)lbuffer->at);
        }
        ImGui::PopStyleColor();
    }
    if (ImGui::GetScrollY() >= ImGui::GetScrollMaxY())
        ImGui::SetScrollHereY(1.0f);
    ImGui::EndChild();
    ImGui::End();

}

typedef enum {
    RESULT_COL_NAME,
    RESULT_COL_ELAPSED_INCLUSIVE,
    RESULT_COL_INCLUSIVE_AVERAGE,
    RESULT_COL_ELAPSED_EXCLUSIVE,
    RESULT_COL_EXCLUSIVE_AVERAGE,
    RESULT_COL_HITCOUNT,
    RESULT_COL_THREAD_ID,
} Result_ColumnID;

static int sort_algo_direction = 1;

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
    else if (left->name.data && right->name.data)
        return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

static int
compare_anchor_average_exclusive(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;

    if (left->hitcount == 0 || right->hitcount == 0)
    {
        return compare_anchor_elapsed_exclusive(lhs, rhs);
    }

    int64_t res = (int64_t)left->elapsed_exclusive / (double)left->hitcount - (int64_t)right->elapsed_exclusive / (double)right->hitcount;
    int sign = (int)(-((int64_t)(((uint64_t)res >> 63) * 2) - 1));

    if (res != 0)
        return sort_algo_direction * sign;
    else if (left->name.data && right->name.data)
        return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

static int
compare_anchor_average_inclusive(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;

    if (left->hitcount == 0 || right->hitcount == 0)
    {
        return compare_anchor_elapsed_inclusive(lhs, rhs);
    }

    int64_t res = (int64_t)left->elapsed_inclusive / (double)left->hitcount - (int64_t)right->elapsed_inclusive / (double)right->hitcount;
    int sign = (int)(-((int64_t)(((uint64_t)res >> 63) * 2) - 1));

    if (res != 0)
        return sort_algo_direction * sign;
    else if (left->name.data && right->name.data)
        return strncmp(left->name.data, right->name.data, left->name.length) * sort_algo_direction;
}

static int
compare_anchor_hitcount(const void* lhs, const void* rhs)
{
    ProfileAnchor* left = (ProfileAnchor*)lhs;
    ProfileAnchor* right = (ProfileAnchor*)rhs;

    int result = left->hitcount - right->hitcount;
    if (result == 0)
    {
        result = compare_anchor_elapsed_exclusive(lhs, rhs) * -1;
        if (result == 0)
            result = strncmp(left->name.data, right->name.data, left->name.length);
    }
    return result * sort_algo_direction;
}

typedef int sort_algo_t(const void*, const void*);
static sort_algo_t* sort_algorithms[] = {
    compare_anchor_name,
    compare_anchor_elapsed_inclusive,
    compare_anchor_average_inclusive,
    compare_anchor_elapsed_exclusive,
    compare_anchor_average_exclusive,
    compare_anchor_hitcount,
};

static double
gui_cycles_to_unit(Gui_State* gui, uint64_t cycles, uint64_t cycles_per_second, uint64_t hitcount)
{
    uint64_t cycle_discount = gui->fixed_cycle_discount * hitcount;
    if (cycle_discount > cycles)
        cycle_discount = cycles;

    switch (gui->time_unit)
    {
        case UNIT_NANOSECONDS:  return cycles_to_ns(cycles - cycle_discount, cycles_per_second);
        case UNIT_MICROSECONDS: return cycles_to_us(cycles - cycle_discount, cycles_per_second);
        case UNIT_SECONDS:      return cycles_to_s(cycles - cycle_discount, cycles_per_second);
        case UNIT_CYCLES:       return cycles - cycle_discount;
        default:
        case UNIT_MILLISECONDS: return cycles_to_ms(cycles - cycle_discount, cycles_per_second);
    }

    return (double)(cycles - (cycle_discount * hitcount));
}

static const char*
gui_time_unit_to_string(TimeUnit unit)
{
    switch (unit)
    {
        case UNIT_NANOSECONDS:  return "Nanoseconds";
        case UNIT_MICROSECONDS: return "Microseconds";
        case UNIT_MILLISECONDS: return "Milliseconds";
        case UNIT_SECONDS:      return "Seconds";
        case UNIT_CYCLES:       return "Cycles";
        default: return "Invalid";
    }
}

void
gui_results(Gui_State* gui)
{
    ProfilingResults* prof = antipessimizer_get_profiling_results();

    const float TEXT_BASE_HEIGHT = ImGui::GetTextLineHeightWithSpacing();
    static ImGuiTableFlags flags =
        ImGuiTableFlags_Resizable | ImGuiTableFlags_Reorderable | ImGuiTableFlags_Hideable | ImGuiTableFlags_Sortable | ImGuiTableFlags_SortMulti
        | ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersOuter | ImGuiTableFlags_BordersV | ImGuiTableFlags_NoBordersInBody
        | ImGuiTableFlags_ScrollY;

    if (ImGui::Begin("Results Sorted"))
    {
        ImGui::SetNextItemWidth(200);
        ImGui::Combo("Unit of time", (int*)&gui->time_unit, "Nanoseconds\0Microseconds\0Milliseconds\0Seconds\0Cycles\0\0");

        ImGui::SameLine();
        ImGui::SetNextItemWidth(400);
        char rs_buf[64] = { 0 };
        ImGui::InputText("Filter", gui->result_filter, sizeof(gui->result_filter));        

        ImGui::SameLine();
        if (ImGui::Button("Clear Thread Filter"))
            gui->selected_thread_id = -1;

        if (ImGui::BeginTable("table_sorting", 7, flags))
        {
            ImGui::TableSetupColumn("Name", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_NAME);
            ImGui::TableSetupColumn("Elapsed exclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_ELAPSED_EXCLUSIVE);
            ImGui::TableSetupColumn("Average exclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_EXCLUSIVE_AVERAGE);
            ImGui::TableSetupColumn("Elapsed inclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_ELAPSED_INCLUSIVE);
            ImGui::TableSetupColumn("Average inclusive", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_INCLUSIVE_AVERAGE);
            ImGui::TableSetupColumn("Hit count", ImGuiTableColumnFlags_DefaultSort, 0.0f, RESULT_COL_HITCOUNT);
            ImGui::TableSetupColumn("Thread ID", ImGuiTableColumnFlags_NoSort, 0.0f, RESULT_COL_THREAD_ID);
            ImGui::TableSetupScrollFreeze(0, 1); // Make row always visible
            ImGui::TableHeadersRow();

            ImGuiTableSortSpecs* sort_specs = ImGui::TableGetSortSpecs();

            uint64_t cycles_per_sec = prof->cycles_per_second;

            if (prof->anchors)
            {
                ImVec4 low_color = { 0, 1, 0, 1 };
                ImVec4 high_color = { 1, 0, 0, 1 };
                ImVec4 color_inclusive = { 0.7f, 0.7f, 0.7f, 1 };
                ImVec4 color_exclusive = { 0.7f, 0.7f, 0.7f, 1 };
                ImVec4 color_avg_inclusive = { 0.7f, 0.7f, 0.7f, 1 };
                ImVec4 color_avg_exclusive = { 0.7f, 0.7f, 0.7f, 1 };
                float max_inclusive = 0;
                float min_inclusive = 0;
                float max_exclusive = 0;
                float min_exclusive = 0;
                float max_avg_inclusive = 0;
                float min_avg_inclusive = 0;
                float max_avg_exclusive = 0;
                float min_avg_exclusive = 0;

                if (sort_specs->SpecsCount > 0)
                {
                    Result_ColumnID uid = (Result_ColumnID)sort_specs->Specs[0].ColumnUserID;

                    if (sort_specs->Specs[0].SortDirection == 1)
                        sort_algo_direction = 1;
                    else
                        sort_algo_direction = -1;
                    qsort(prof->anchors, (size_t)array_length(prof->anchors), sizeof(prof->anchors[0]), sort_algorithms[uid]);

                    if (array_length(prof->anchors) > 0)
                    {
                        if (uid == RESULT_COL_ELAPSED_INCLUSIVE)
                        {
                            max_inclusive = log2f(prof->anchors[0].elapsed_inclusive / MILLISECOND);
                            min_inclusive = log2f(prof->anchors[array_length(prof->anchors)-1].elapsed_inclusive / MILLISECOND);
                        }

                        if (uid == RESULT_COL_INCLUSIVE_AVERAGE && prof->anchors[0].hitcount > 0)
                        {
                            max_avg_inclusive = log2f(prof->anchors[0].elapsed_inclusive / prof->anchors[0].hitcount);
                            min_avg_inclusive = log2f(prof->anchors[array_length(prof->anchors) - 1].elapsed_inclusive / (double)prof->anchors[0].hitcount);
                        }

                        if (uid == RESULT_COL_ELAPSED_EXCLUSIVE)
                        {
                            max_exclusive = log2f(prof->anchors[0].elapsed_exclusive / MILLISECOND);
                            min_exclusive = log2f(prof->anchors[array_length(prof->anchors) - 1].elapsed_exclusive / MILLISECOND);
                        }

                        if (uid == RESULT_COL_EXCLUSIVE_AVERAGE && prof->anchors[0].hitcount > 0)
                        {
                            max_avg_exclusive = log2f(prof->anchors[0].elapsed_exclusive / prof->anchors[0].hitcount);
                            min_avg_exclusive = log2f(prof->anchors[array_length(prof->anchors) - 1].elapsed_exclusive / (double)prof->anchors[0].hitcount);
                        }

                        if (sort_algo_direction == 1)
                        {
                            SWAP_FLOAT(max_inclusive, min_inclusive);
                            SWAP_FLOAT(max_exclusive, min_exclusive);
                            SWAP_FLOAT(max_avg_inclusive, min_avg_inclusive);
                            SWAP_FLOAT(max_avg_exclusive, min_avg_exclusive);
                        }
                    }
                }

                ImGuiListClipper clipper;
                ProfileAnchor* anchors = prof->anchors;

                bool has_filter = false;

                // Filter depending on the filter textbox by string
                if (gui->result_filter[0] != 0)
                {
                    has_filter = true;
                    anchors = array_new(ProfileAnchor);
                    for (int i = 0; i < array_length(prof->anchors); ++i)
                    {
                        ProfileAnchor* item = &prof->anchors[i];
                        String unm_name = unmangle_name(item->name);
                        if (!strstr(tmp_str_lowercase(unm_name).data, tmp_str_lowercase(tmp_str_new_c(gui->result_filter)).data))
                        {
                            continue;
                        }
                        array_push(anchors, *item);
                    }
                }

                // Filter depending on ThreadID
                if (gui->selected_thread_id != -1)
                {
                    if(!has_filter)
                        anchors = array_new(ProfileAnchor);
                    has_filter = true;
                    for (int i = 0; i < array_length(prof->anchors); ++i)
                    {
                        ProfileAnchor* item = &prof->anchors[i];
                        if (item->thread_id != gui->selected_thread_id)
                        {
                            continue;
                        }
                        array_push(anchors, *item);
                    }
                }
                if(!has_filter)
                    anchors = prof->anchors;
                
                clipper.Begin(array_length(anchors));

                bool changed_selection = false;

                while (clipper.Step())
                {
                    for (int row_n = clipper.DisplayStart; row_n < clipper.DisplayEnd; row_n++)
                    {
                        ProfileAnchor* item = &anchors[row_n];
                        if (max_inclusive > 0 && (max_inclusive - min_inclusive > 0))
                        {
                            float elapsed_ms = log2f(item->elapsed_inclusive / MILLISECOND);
                            float factor = (elapsed_ms - min_inclusive) / (max_inclusive - min_inclusive);
                            color_inclusive = interpolate_color(low_color, high_color, factor);
                        }
                        if (max_exclusive > 0 && (max_exclusive - min_exclusive > 0))
                        {
                            float elapsed_ms = log2f(item->elapsed_exclusive / MILLISECOND);
                            float factor = (elapsed_ms - min_exclusive) / (max_exclusive - min_exclusive);
                            color_exclusive = interpolate_color(low_color, high_color, factor);
                        }
                        if (max_avg_exclusive > 0 && item->hitcount > 0)
                        {
                            float elapsed_ms = log2f(item->elapsed_exclusive / (double)item->hitcount);
                            float factor = (elapsed_ms - min_avg_exclusive) / (max_avg_exclusive - min_avg_exclusive);
                            color_avg_exclusive = interpolate_color(low_color, high_color, factor);
                        }
                        if (max_avg_inclusive > 0 && item->hitcount > 0)
                        {
                            float elapsed_ms = log2f(item->elapsed_inclusive / (double)item->hitcount);
                            float factor = (elapsed_ms - min_avg_inclusive) / (max_avg_inclusive - min_avg_inclusive);
                            color_avg_inclusive = interpolate_color(low_color, high_color, factor);
                        }

                        String unm_name = unmangle_name(item->name);

                        if(item->name.data)
                            ImGui::PushID(item->name.data);
                        else
                        {
                            char buf[32] = { 0 };
                            sprintf(buf, "0x%llx", item->address);
                            ImGui::PushID(buf);
                        }
                        ImGui::TableNextRow();
                        ImGui::TableNextColumn();
                        if (unm_name.length > 0)
                            ImGui::Text("%s", unm_name.data);
                        else
                            ImGui::Text("0x%llx", item->address);
                        ImGui::TableNextColumn();

                        ImGui::TextColored(color_exclusive, "%.4f", gui_cycles_to_unit(gui, anchors[row_n].elapsed_exclusive, cycles_per_sec, anchors[row_n].hitcount));
                        ImGui::TableNextColumn();
                        double average_exclusive = 0.0;
                        if(anchors[row_n].hitcount > 0)
                            average_exclusive = gui_cycles_to_unit(gui, anchors[row_n].elapsed_exclusive, cycles_per_sec, anchors[row_n].hitcount) / anchors[row_n].hitcount;
                        ImGui::TextColored(color_avg_exclusive, "%.4f", average_exclusive);
                        ImGui::TableNextColumn();
                        
                        ImGui::TextColored(color_inclusive, "%.4f", gui_cycles_to_unit(gui, anchors[row_n].elapsed_inclusive, cycles_per_sec, anchors[row_n].hitcount));
                        ImGui::TableNextColumn();
                        double average_inclusive = 0.0;
                        if (anchors[row_n].hitcount > 0)
                            average_inclusive = gui_cycles_to_unit(gui, anchors[row_n].elapsed_inclusive, cycles_per_sec, anchors[row_n].hitcount) / anchors[row_n].hitcount;
                        ImGui::TextColored(color_avg_inclusive, "%.4f", average_inclusive);
                        ImGui::TableNextColumn();

                        ImGui::Text("%lld", item->hitcount);
                        ImGui::TableNextColumn();
                        String thread_name = antipessimizer_get_thread_name(item->thread_id);
                        bool selected = gui->selected_thread_id == item->thread_id;

                        bool prev_selected = selected;
                        
                        if (thread_name.length > 0)
                        {
                            ImGui::Selectable(thread_name.data, &selected, ImGuiSelectableFlags_None);
                        }
                        else
                        {
                            char bf[32] = { 0 };
                            sprintf(bf, "%d", item->thread_id);
                            ImGui::Selectable(bf, &selected, ImGuiSelectableFlags_None);
                        }

                        if (!changed_selection && prev_selected != selected)
                        {
                            if (selected)
                                gui->selected_thread_id = item->thread_id;
                            else
                                gui->selected_thread_id = -1;
                        }

                        ImGui::PopID();
                    }
                }

                if (has_filter)
                    array_free(anchors);
            }
            ImGui::EndTable();
        }
    }
    ImGui::End();
}

void
gui_load_config(Gui_State* gui)
{
    int64_t fsize = 0;
    char* data = (char*)os_file_read("antipessimizer.config", &fsize);
    if (data)
    {        
        const char* at = data;
        hpa_parse_keyword(&at, "Filepath:");
        hpa_parse_whitespace(&at);
        at++;
        int i = 0;
        while (*at != '\'' && i < ARRAY_LENGTH(gui->process_filepath))
            gui->process_filepath[i++] = *at++;
        at++;
        hpa_parse_whitespace(&at);

        hpa_parse_keyword(&at, "ResultFilter:");
        hpa_parse_whitespace(&at);
        at++;
        i = 0;
        while (*at != '\'' && i < ARRAY_LENGTH(gui->result_filter))
            gui->result_filter[i++] = *at++;
        at++;
        hpa_parse_whitespace(&at);

        hpa_parse_keyword(&at, "UnitFilter:");
        hpa_parse_whitespace(&at);
        at++;
        i = 0;
        while (*at != '\'' && i < ARRAY_LENGTH(gui->unit_filter))
            gui->unit_filter[i++] = *at++;
        at++;
        hpa_parse_whitespace(&at);

        if (at < data + fsize)
        {
            if (hpa_parse_keyword(&at, "TimeUnit:"))
            {
                hpa_parse_whitespace(&at);
                int tunit_len = hpa_parse_identifier(at);
                String ts = tmp_str_new_len_c((char*)at, tunit_len);
                if (string_equal_char((char*)"Nanoseconds", ts))
                    gui->time_unit = UNIT_NANOSECONDS;
                else if (string_equal_char((char*)"Microseconds", ts))
                    gui->time_unit = UNIT_MICROSECONDS;
                else if (string_equal_char((char*)"Milliseconds", ts))
                    gui->time_unit = UNIT_MILLISECONDS;
                else if (string_equal_char((char*)"Seconds", ts))
                    gui->time_unit = UNIT_SECONDS;
                at += tunit_len;
            }
        }

        hpa_parse_whitespace(&at);
        if (at < data + fsize)
        {
            if (hpa_parse_keyword(&at, "FixedCycleDiscount:"))
            {
                hpa_parse_whitespace(&at);

                gui->fixed_cycle_discount = hpa_parse_uint64(&at);
            }
        }
        else
        {
            gui->fixed_cycle_discount = 262;
        }
    }
    else
        printf("Config file not found\n");

    gui->loaded_units = array_new(String);
    fsize = 0;
    char* mods = (char*)os_file_read("antipessimizer.modules", &fsize);
    if (mods)
    {
        const char* at = mods;
        if (hpa_parse_keyword(&at, "SelectedModules:"))
        {
            hpa_parse_whitespace(&at);

            at++;
            char c = *at;
            while (c != ']' && c != '\0' && c != '\n')
            {
                String s;
                s.data = (char*)at;
                s.length = hpa_parse_until_char(&at, ',') - 1;
                array_push(gui->loaded_units, s);
                c = *at;
                if (s.length == 0)
                    break;
            }
        }
    }
}

void
gui_init(Gui_State* gui)
{
    gui->procedure_last_selected = -1;
    gui->selected_thread_id = -1;
    gui->process_filepath[0] = 0;
    gui->unit_filter[0] = 0;
    gui->realtime_results = false;
    gui->time_unit = UNIT_MILLISECONDS;
    gui->fixed_cycle_discount = 0;

    gui_load_config(gui);

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
gui_render(Gui_State* gui)
{
    ImGui::NewFrame();
    ImGui::DockSpaceOverViewport(ImGui::GetMainViewport());

    {
        gui_selection_window(gui);
        gui_results(gui);
    }

    ImGui::Render();

    tmp_wstr_clear_arena();
}

void
gui_save_config(Gui_State* gui)
{
    FILE* config = fopen("antipessimizer.config", "wb");
    fprintf(config, "Filepath: '%s'\n", gui->process_filepath);
    fprintf(config, "ResultFilter: '%s'\n", gui->result_filter);
    fprintf(config, "UnitFilter: '%s'\n", gui->unit_filter);
    fprintf(config, "TimeUnit: %s\n", gui_time_unit_to_string(gui->time_unit));
    fprintf(config, "FixedCycleDiscount: %llu\n", gui->fixed_cycle_discount);
    fclose(config);

    antipessimizer_save_modules_selected();
}