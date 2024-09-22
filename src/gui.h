#pragma once
#include "os.h"
extern "C" {
#include "string_utils.h"
}

#define MAX_INPUT 128

typedef enum {
	UNIT_NANOSECONDS,
	UNIT_MICROSECONDS,
	UNIT_MILLISECONDS,
	UNIT_SECONDS,
	UNIT_CYCLES,
} TimeUnit;

typedef struct {
	char process_filepath[MAX_PATH];
	char unit_filter[MAX_INPUT];
	char result_filter[MAX_INPUT];

	int  procedure_last_selected;
	bool realtime_results;

	int32_t selected_thread_id;

	String* loaded_units;

	TimeUnit time_unit;
	uint64_t fixed_cycle_discount;
} Gui_State;

void gui_render(Gui_State* gui);
void gui_init(Gui_State* gui);
void gui_save_config(Gui_State* gui);