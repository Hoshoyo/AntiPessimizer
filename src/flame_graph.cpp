#include "gui.h"
#include <imgui.h>
#include <stdint.h>
#include <stdlib.h>
#include <light_array.h>

void
draw_flame_rect(ImDrawList* draw_list, int id, ImVec2 bl, float width, float height, float scale, uint64_t start, uint64_t end)
{
    uint32_t color = 0xffaaaaaa;
    if (ImGui::IsMouseHoveringRect(bl, ImVec2(bl.x + MAX(1, width * scale), bl.y + height)))
    {
        color = 0xffffffff;
        ImGui::BeginTooltip();
        {
            ImGui::Text("0x%x %lld -> %lld", id, start, end);
            ImGui::EndTooltip();
        }
    }

    draw_list->AddRectFilled(bl, ImVec2(bl.x + MAX(1, width * scale), bl.y + height), color);
    draw_list->AddRect(bl, ImVec2(bl.x + width * scale, bl.y + height), 0x44000000);
}

typedef enum {
    FLAME_NONE = 0,
    FLAME_ENTER_BLOCK = 1,
    FLAME_EXIT_BLOCK = 2,
} FlameType;

#pragma pack(push, 1)
typedef struct {
    uint64_t addr;
    uint64_t start;
} FlameEnterBlock;

typedef struct {
    uint64_t end;
} FlameExitBlock;

typedef struct {
    uint32_t type;
    uint32_t thread_id;
    int32_t  depth;
    union {
        FlameEnterBlock enter;
        FlameExitBlock exit;
    };
} FlameEntry;
#pragma pack(pop)

typedef struct {
    FlameEnterBlock enter;
    ImVec2 p;
} FlameStack;

void
gui_flame_graph(Gui_State* gui)
{
    if (!gui->flame_graph_data && os_file_exists((char*)"out.flame"))
    {
        //gui->flame_graph_file = fopen("out.flame", "rb");
        gui->flame_graph_data = os_file_read("out.flame", &gui->flame_graph_data_size);
    }

    if (!gui->flame_graph_data)
        return;

    float wheel = ImGui::GetIO().MouseWheel;

    static float scale = 1.0f;
    static float width = 10.0f;
    scale += wheel;
    if (scale < 1.0f) scale = 1.0f;

    ImDrawList* draw_list = ImGui::GetWindowDrawList();
    ImVec2 p = ImGui::GetCursorScreenPos();
    float start = 0.0f;

    FlameStack stack[32] = { 0 };
    for (int i = 0; i < ARRAY_LENGTH(stack); ++i)
    {
        stack[i].p = p;
        stack[i].p.y += 22.0f * i;
    }

    FlameEntry* at = (FlameEntry*)gui->flame_graph_data;
    uint64_t first = at->enter.start;
    for (int i = 0; i < 100; ++i)
    //int  i = 0;
    //while (true)
    {
        if (*(char*)at == 0)
            break;
        FlameEntry* entry = at;
        switch (entry->type)
        {
            case FLAME_ENTER_BLOCK: {
                stack[entry->depth].enter = entry->enter;
            } break;
            case FLAME_EXIT_BLOCK: {
                FlameStack* eb = &stack[entry->depth];
                int64_t cycles_elapsed = (int64_t)entry->exit.end - (int64_t)eb->enter.start;

                width = cycles_elapsed / 1000000.0;
                ImVec2 pp = eb->p;

                float distance_from_first = ((eb->enter.start - first) / 1000000.0f) * scale;
                pp.x += distance_from_first;
                draw_flame_rect(draw_list, i, pp, width, 20.0f, scale, eb->enter.start, entry->exit.end);
                start = MAX(start, pp.x + width);

                at = (FlameEntry*)((char*)at - sizeof(uint64_t));
            } break;
        }
        //i++;
        at++;
    }

    ImGui::Dummy(ImVec2(start, 0));
}