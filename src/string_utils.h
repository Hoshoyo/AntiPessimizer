#pragma once
#include <stdint.h>
#include <hoht.h>
#include <light_arena.h>
#include <stdarg.h>

typedef struct {
	int64_t  length;
	wchar_t* data;
} Wstring;

void    wstring_init_globals();

Wstring unique_wstring_new_length(Hoht_Table* table, Light_Arena* arena, wchar_t* str, int64_t len, int reuse);
Wstring unique_wstring_new(Hoht_Table* table, Light_Arena* arena, wchar_t* str);
Wstring unique_wstring_concatenate(Hoht_Table* table, Light_Arena* arena, Wstring s1, Wstring s2);
int     unique_wstring_equal(Wstring s1, Wstring s2);
Wstring unique_wstring_substring(Hoht_Table* table, Light_Arena* arena, Wstring s, int64_t index, int64_t length);
Wstring unique_wstring_uppercase(Hoht_Table* table, Light_Arena* arena, Wstring s);
Wstring unique_wstring_lowercase(Hoht_Table* table, Light_Arena* arena, Wstring s);
Wstring unique_wstring_trim(Hoht_Table* table, Light_Arena* arena, Wstring s);
int64_t wstring_index_of(Wstring s, wchar_t c);
Wstring unique_wstring_print(Hoht_Table* table, Light_Arena* arena, wchar_t* fmt, ...);
int     wstring_has_prefix(Wstring prefix, Wstring s);
int     wstring_has_prefix_wchar(wchar_t* prefix, Wstring s);
int     wstring_equal(Wstring s1, Wstring s2);
int     wstring_equal_wchar(wchar_t* s1, Wstring s2);

// Versions of the functions using internal global tables
Wstring uwstr_new_c(char* str);
Wstring uwstr_new_len_c(char* str, int64_t len);

Wstring uwstr_copy(Wstring s);
Wstring uwstr_new(wchar_t* str);
Wstring uwstr_new_len(wchar_t* str, int64_t len);
Wstring uwstr_concat(Wstring s1, Wstring s2);
int     uwstr_equal(Wstring s1, Wstring s2);
Wstring uwstr_substring(Wstring s, int64_t index, int64_t length);
Wstring uwstr_uppercase(Wstring s);
Wstring uwstr_lowercase(Wstring s);
Wstring uwstr_trim(Wstring s);
int     wstr_has_prefix(Wstring prefix, Wstring s);
int     wstr_has_prefix_wchar(wchar_t* prefix, Wstring s);
int     wstr_equal(Wstring s1, Wstring s2);
int     wstr_equal_wchar(wchar_t* s1, Wstring s2);

// Versions of the functions using internal global tables
Wstring tmp_wstr_new_c(char* str);
Wstring tmp_wstr_new_len_c(char* str, int64_t len);

Wstring tmp_wstr_new(wchar_t* str);
Wstring tmp_wstr_new_len(wchar_t* str, int64_t len);
Wstring tmp_wstr_concat(Wstring s1, Wstring s2);
int     tmp_wstr_equal(Wstring s1, Wstring s2);
Wstring tmp_wstr_substring(Wstring s, int64_t index, int64_t length);
Wstring tmp_wstr_uppercase(Wstring s);
Wstring tmp_wstr_lowercase(Wstring s);
Wstring tmp_wstr_trim(Wstring s);

void tmp_wstr_clear_arena();

// - Normal c string

typedef struct {
	int64_t  length;
	char* data;
} String;

void   string_init_globals();

String unique_string_new_length(Hoht_Table* table, Light_Arena* arena, char* str, int64_t len, int reuse);
String unique_string_new(Hoht_Table* table, Light_Arena* arena, char* str);
String unique_string_concatenate(Hoht_Table* table, Light_Arena* arena, String s1, String s2);
int    unique_string_equal(String s1, String s2);
String unique_string_substring(Hoht_Table* table, Light_Arena* arena, String s, int64_t index, int64_t length);
String unique_string_uppercase(Hoht_Table* table, Light_Arena* arena, String s);
String unique_string_lowercase(Hoht_Table* table, Light_Arena* arena, String s);
String unique_string_trim(Hoht_Table* table, Light_Arena* arena, String s);
int64_t string_index_of(String s, char c);
String unique_string_print(Hoht_Table* table, Light_Arena* arena, char* fmt, ...);
int    string_has_prefix(String prefix, String s);
int    string_has_prefix_char(char* prefix, String s);
int    string_equal(String s1, String s2);
int    string_equal_char(char* s1, String s2);

// Versions of the functions using internal global tables
String ustr_new_c(char* str);
String ustr_new_len_c(char* str, int64_t len);

String ustr_copy(String s);
String ustr_new(char* str);
String ustr_new_len(char* str, int64_t len);
String ustr_concat(String s1, String s2);
int    ustr_equal(String s1, String s2);
String ustr_substring(String s, int64_t index, int64_t length);
String ustr_uppercase(String s);
String ustr_lowercase(String s);
String ustr_trim(String s);
int    str_has_prefix(String prefix, String s);
int    str_has_prefix_char(char* prefix, String s);
int    str_equal(String s1, String s2);
int    str_equal_char(char* s1, String s2);

// Versions of the functions using internal global tables
String tmp_str_new_c(char* str);
String tmp_str_new_len_c(char* str, int64_t len);

String tmp_str_new(char* str);
String tmp_str_new_len(char* str, int64_t len);
String tmp_str_concat(String s1, String s2);
int    tmp_str_equal(String s1, String s2);
String tmp_str_substring(String s, int64_t index, int64_t length);
String tmp_str_uppercase(String s);
String tmp_str_lowercase(String s);
String tmp_str_trim(String s);