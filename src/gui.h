#pragma once
#include "os.h"

#define MAX_INPUT 128

typedef struct {
	char process_filepath[MAX_PATH];
	char unit_filter[MAX_INPUT];
	char result_filter[MAX_INPUT];

	int  procedure_last_selected;
	bool realtime_results;
} Gui_State;

void gui_render(Gui_State* gui);
void gui_init(Gui_State* gui);