#pragma once
#include "os.h"

#define MAX_INPUT 128

typedef struct {
	char process_filepath[MAX_PATH];
	char unit_filter[MAX_INPUT];
	char result_filter[MAX_INPUT];

	int  procedure_last_selected;
	bool realtime_results;

	int32_t selected_thread_id;

	void*   flame_graph_data;
	int64_t flame_graph_data_size;
} Gui_State;

void gui_render(Gui_State* gui);
void gui_init(Gui_State* gui);
void gui_save_config(Gui_State* gui);
void gui_flame_graph(Gui_State* gui);