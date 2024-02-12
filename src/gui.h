#pragma once
#include "os.h"

#define MAX_INPUT 128

typedef struct {
	char process_filepath[MAX_PATH];
	char unit_filter[MAX_INPUT];

	int  procedure_last_selected;
	bool realtime_results;
} Gui_State;

void gui_render();
void gui_init();