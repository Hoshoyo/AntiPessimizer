#define HOHT_SERIALIZE_IMPLEMENTATION
#define HOHT_IMPLEMENTATION
#define LIGHT_ARENA_IMPLEMENT
#include <hoht.h>
#include <light_arena.h>
#include <meow_hash.h>
#include <unicode.h>
#include <stdio.h>
#include <assert.h>

#include "string_utils.h"

static Light_Arena* string_arena;
static Hoht_Table string_table;
static Hoht_Table normal_string_table;

static Light_Arena* tmp_string_arena;
static Hoht_Table tmp_string_table;
static Hoht_Table tmp_normal_string_table;

static wchar_t* empty_string = L"";
static char* normal_empty_string = "";

static void* allocate(size_t s)
{
	return calloc(1, s);
}

void 
wstring_init_globals()
{
	if (!string_arena)
		string_arena = arena_create(1024 * 1024 * 8);
	hoht_new(&string_table, 1024 * 16, sizeof(Wstring), 0.5f, allocate, free);

	if (!tmp_string_arena)
		tmp_string_arena = arena_create(1024 * 1024 * 8);
	hoht_new(&tmp_string_table, 1024 * 16, sizeof(Wstring), 0.5f, allocate, free);
}

Wstring unique_wstring_new_length(Hoht_Table* table, Light_Arena* arena, wchar_t* str, int64_t len, int reuse)
{
	Wstring result;
	result.length = len;

	if (len == 0)
	{
		result.data = empty_string;
		return result;
	}

	__m128i hash = MeowHash(MeowDefaultSeed, result.length * sizeof(wchar_t), str);
	void* entry = hoht_get_value_hashed(table, hash);

	if (entry)
	{
		result = *(Wstring*)entry;
	}
	else if (reuse)
	{
		result.data = str;
		hoht_push_length(table, (const char*)str, (int)(result.length * sizeof(wchar_t)), &result);
	}
	else
	{
		result.data = (wchar_t*)arena_alloc(arena, (result.length + 1) * sizeof(wchar_t));
		if (result.data)
		{
			memcpy(result.data, str, result.length * sizeof(wchar_t));
			result.data[result.length] = 0;
		}
		hoht_push_length(table, (const char*)str, (int)(result.length * sizeof(wchar_t)), &result);
	}
	return result;
}

Wstring unique_wstring_new(Hoht_Table* table, Light_Arena* arena, wchar_t* str)
{
	return unique_wstring_new_length(table, arena, str, (int64_t)wcslen(str), 0);
}

Wstring unique_wstring_concatenate(Hoht_Table* table, Light_Arena* arena, Wstring s1, Wstring s2)
{
	int64_t new_length = (s1.length + s2.length);
	wchar_t* mem = (wchar_t*)calloc(1, (new_length + 1) * sizeof(wchar_t));
	memcpy(mem, s1.data, s1.length * sizeof(wchar_t));
	memcpy(mem + s1.length, s2.data, s2.length * sizeof(wchar_t));
	mem[new_length] = 0;

	Wstring new_str = unique_wstring_new_length(table, arena, mem, new_length, 0);
	if (new_str.data == mem)
	{
		wchar_t* newmem = arena_alloc(arena, (new_length + 1) * sizeof(wchar_t));
		memcpy(newmem, mem, (new_length + 1) * sizeof(wchar_t));
		new_str.data = newmem;
	}
	free(mem);
	return new_str;
}

int unique_wstring_equal(Wstring s1, Wstring s2)
{
	return (s1.data == s2.data) && (s1.length == s2.length);
}

Wstring unique_wstring_substring(Hoht_Table* table, Light_Arena* arena, Wstring s, int64_t index, int64_t length)
{
	if (index > 0 && index < s.length)
	{
		if (length >= s.length - index)
			length = s.length - index - 1;
		return unique_wstring_new_length(table, arena, s.data + index, length, 0);
	}
	return s;
}

Wstring unique_wstring_uppercase(Hoht_Table* table, Light_Arena* arena, Wstring s)
{
	wchar_t* mem = (wchar_t*)calloc(1, (s.length + 1) * sizeof(wchar_t));
	memcpy(mem, s.data, s.length * sizeof(wchar_t));
	mem[s.length] = 0;

	for (int i = 0; i < s.length; ++i)
	{
		wchar_t c = mem[i];
		if (c >= 'a' && c <= 'z')
			mem[i] = c - 'a' + 'A';
	}
	Wstring result = unique_wstring_new_length(table, arena, mem, s.length, 0);
	if (result.data == mem)
	{
		wchar_t* newmem = arena_alloc(arena, (s.length + 1) * sizeof(wchar_t));
		memcpy(newmem, mem, (s.length + 1) * sizeof(wchar_t));
		result.data = newmem;
	}
	free(mem);
	return result;
}

Wstring unique_wstring_lowercase(Hoht_Table* table, Light_Arena* arena, Wstring s)
{
	wchar_t* mem = (wchar_t*)calloc(1, (s.length + 1) * sizeof(wchar_t));//arena_alloc(arena, (s.length + 1) * sizeof(wchar_t));
	memcpy(mem, s.data, s.length * sizeof(wchar_t));
	mem[s.length] = 0;

	for (int i = 0; i < s.length; ++i)
	{
		wchar_t c = mem[i];
		if (c >= 'A' && c <= 'Z')
			mem[i] = c - 'A' + 'a';
	}
	Wstring result = unique_wstring_new_length(table, arena, mem, s.length, 0);
	if (result.data == mem)
	{
		wchar_t* newmem = arena_alloc(arena, (s.length + 1) * sizeof(wchar_t));
		memcpy(newmem, mem, (s.length + 1) * sizeof(wchar_t));
		result.data = newmem;
	}
	free(mem);
	return result;
}

Wstring unique_wstring_trim(Hoht_Table* table, Light_Arena* arena, Wstring s)
{
	int64_t cbefore = 0;
	int64_t cafter = 0;

	for (int i = 0; i < s.length; ++i)
	{
		wchar_t c = s.data[i];

		if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\v')
			cbefore++;
		else
			break;
	}
	for (int64_t i = s.length - 1; i >= 0; --i)
	{
		wchar_t c = s.data[i];

		if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\v')
			cafter++;
		else
			break;
	}

	return unique_wstring_substring(table, arena, s, cbefore, s.length - cbefore - cafter);
}

int64_t wstring_index_of(Wstring s, wchar_t c)
{
	int64_t result = -1;
	for (int i = 0; i < s.length; ++i)
		if (s.data[i] == c)
			return i;
	return result;
}

Wstring unique_wstring_print(Hoht_Table* table, Light_Arena* arena, wchar_t* fmt, ...)
{
	va_list args;
	va_start(args, fmt);

	wchar_t buffer[256] = { 0 };
	size_t alloc_size = sizeof(buffer);
	int len = _vsnwprintf_s(buffer, alloc_size / sizeof(wchar_t), (alloc_size - 1) / sizeof(wchar_t) - 1, fmt, args);
	int reuse = 0;

	wchar_t* mem = buffer;

	while (len == -1)
	{
		alloc_size *= 2;
		mem = (wchar_t*)calloc(1, alloc_size);
		len = _vsnwprintf_s(mem, alloc_size / sizeof(wchar_t), (alloc_size - 1) / sizeof(wchar_t), fmt, args);
		reuse = 1;
		if (len == -1)
			free(mem);
	}

	va_end(args);

	Wstring result = unique_wstring_new_length(table, arena, mem, len, 0);
	free(mem);

	return result;
}

int wstring_has_prefix(Wstring prefix, Wstring s)
{
	if (s.length < prefix.length)
		return 0;
	for (int i = 0; i < prefix.length; ++i)
	{
		if (prefix.data[i] != s.data[i])
			return 0;
	}
	return 1;
}

int wstring_has_prefix_wchar(wchar_t* prefix, Wstring s)
{
	for (int i = 0; i < s.length && prefix[i] != 0; ++i)
	{
		if (prefix[i] != s.data[i])
			return 0;
	}
	return 1;
}

int wstring_equal(Wstring s1, Wstring s2)
{
	if (s1.length != s2.length)
		return 0;
	for (int i = 0; i < s1.length; ++i)
	{
		if (s1.data[i] != s2.data[i])
			return 0;
	}
	return 1;
}

int wstring_equal_wchar(wchar_t* s1, Wstring s2)
{
	int i = 0;
	for (; i < s2.length && s1[i] != 0; ++i)
	{
		if (s1[i] != s2.data[i])
			return 0;
	}
	return (i == s2.length) && (s1[i] == 0);
}

Wstring 
uwstr_new(wchar_t* str)
{
	return unique_wstring_new(&string_table, string_arena, str);
}

Wstring 
uwstr_new_len(wchar_t* str, int64_t len)
{
	return unique_wstring_new_length(&string_table, string_arena, str, len, 1);
}

Wstring 
uwstr_copy(Wstring s)
{
	return uwstr_new_len(s.data, s.length);
}

Wstring 
uwstr_concat(Wstring s1, Wstring s2)
{
	return unique_wstring_concatenate(&string_table, string_arena, s1, s2);
}

int
uwstr_equal(Wstring s1, Wstring s2)
{
	return unique_wstring_equal(s1, s2);
}

Wstring 
uwstr_substring(Wstring s, int64_t index, int64_t length)
{
	return unique_wstring_substring(&string_table, string_arena, s, index, length);
}

Wstring 
uwstr_uppercase(Wstring s)
{
	return unique_wstring_uppercase(&string_table, string_arena, s);
}

Wstring 
uwstr_lowercase(Wstring s)
{
	return unique_wstring_lowercase(&string_table, string_arena, s);
}

Wstring 
uwstr_trim(Wstring s)
{
	return unique_wstring_trim(&string_table, string_arena, s);
}

int
wstr_has_prefix(Wstring prefix, Wstring s)
{
	return wstring_has_prefix(prefix, s);
}

int
wstr_has_prefix_wchar(wchar_t* prefix, Wstring s)
{
	return wstring_has_prefix_wchar(prefix, s);
}

int
wstr_equal(Wstring s1, Wstring s2)
{
	return wstring_equal(s1, s2);
}

int
wstr_equal_wchar(wchar_t* s1, Wstring s2)
{
	return wstring_equal_wchar(s1, s2);
}

// Temporary

Wstring
tmp_wstr_new(wchar_t* str)
{
	return unique_wstring_new(&tmp_string_table, tmp_string_arena, str);
}

Wstring
tmp_wstr_new_len(wchar_t* str, int64_t len)
{
	return unique_wstring_new_length(&tmp_string_table, tmp_string_arena, str, len, 1);
}

Wstring
tmp_wstr_concat(Wstring s1, Wstring s2)
{
	return unique_wstring_concatenate(&tmp_string_table, tmp_string_arena, s1, s2);
}

int
tmp_wstr_equal(Wstring s1, Wstring s2)
{
	return unique_wstring_equal(s1, s2);
}

Wstring
tmp_wstr_substring(Wstring s, int64_t index, int64_t length)
{
	return unique_wstring_substring(&tmp_string_table, tmp_string_arena, s, index, length);
}

Wstring
tmp_wstr_uppercase(Wstring s)
{
	return unique_wstring_uppercase(&tmp_string_table, tmp_string_arena, s);
}

Wstring
tmp_wstr_lowercase(Wstring s)
{
	return unique_wstring_lowercase(&tmp_string_table, tmp_string_arena, s);
}

Wstring
tmp_wstr_trim(Wstring s)
{
	return unique_wstring_trim(&tmp_string_table, tmp_string_arena, s);
}

Wstring 
tmp_wstr_new_c(char* str)
{
	size_t len = strlen(str);
	wchar_t* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(wchar_t));
	res[len] = 0;
	size_t utf16len = utf8_to_utf16(str, len, res, (len + 1) * sizeof(wchar_t));
	return tmp_wstr_new_len(res, utf16len);
}

Wstring 
tmp_wstr_new_len_c(char* str, int64_t len)
{
	wchar_t* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(wchar_t));
	res[len] = 0;
	size_t utf16len = utf8_to_utf16(str, len, res, (len + 1) * sizeof(wchar_t));
	return tmp_wstr_new_len(res, utf16len);
}

Wstring
uwstr_new_c(char* str)
{
	size_t len = strlen(str);
	wchar_t* res = arena_alloc(string_arena, (len + 1) * sizeof(wchar_t));
	res[len] = 0;
	size_t utf16len = utf8_to_utf16(str, len, res, (len + 1) * sizeof(wchar_t));
	Wstring result = unique_wstring_new_length(&string_table, string_arena, res, utf16len, 1);
	return result;
}

Wstring
uwstr_new_len_c(char* str, int64_t len)
{
	wchar_t* res = arena_alloc(string_arena, (len + 1) * sizeof(wchar_t));
	res[len] = 0;
	size_t utf16len = utf8_to_utf16(str, len, res, (len + 1) * sizeof(wchar_t));
	Wstring result = unique_wstring_new_length(&string_table, string_arena, res, utf16len, 1);
	return result;
}

void 
tmp_wstr_clear_arena()
{
	arena_clear(tmp_string_arena);
	hoht_clear(&tmp_normal_string_table);
	//hoht_new(&tmp_normal_string_table, 1024 * 16, sizeof(Wstring), 0.5f, allocate, free);
}


// - Normal strings

void
string_init_globals()
{
	if(!string_arena)
		string_arena = arena_create(1024 * 1024 * 8);
	hoht_new(&normal_string_table, 1024 * 16, sizeof(Wstring), 0.5f, allocate, free);

	if(!tmp_string_arena)
		tmp_string_arena = arena_create(1024 * 1024 * 8);
	hoht_new(&tmp_normal_string_table, 1024 * 16, sizeof(Wstring), 0.5f, allocate, free);
}

String unique_string_new_length(Hoht_Table* table, Light_Arena* arena, char* str, int64_t len, int reuse)
{
	String result;
	result.length = len;

	if (len == 0)
	{
		result.data = normal_empty_string;
		return result;
	}

	__m128i hash = MeowHash(MeowDefaultSeed, result.length * sizeof(char), str);
	void* entry = hoht_get_value_hashed(table, hash);

	if (entry)
	{
		result = *(String*)entry;
	}
	else if (reuse)
	{
		result.data = str;
		hoht_push_length(table, (const char*)str, (int)(result.length * sizeof(char)), &result);
	}
	else
	{
		result.data = (char*)arena_alloc(arena, (result.length + 1) * sizeof(char));
		if (result.data)
		{
			memcpy(result.data, str, result.length * sizeof(char));
			result.data[result.length] = 0;
		}
		hoht_push_length(table, (const char*)str, (int)(result.length * sizeof(char)), &result);
	}
	return result;
}

String unique_string_new(Hoht_Table* table, Light_Arena* arena, char* str)
{
	return unique_string_new_length(table, arena, str, (int64_t)strlen(str), 0);
}

String unique_string_concatenate(Hoht_Table* table, Light_Arena* arena, String s1, String s2)
{
	int64_t new_length = (s1.length + s2.length);
	char* mem = (char*)calloc(1, (new_length + 1) * sizeof(char));
	memcpy(mem, s1.data, s1.length * sizeof(char));
	memcpy(mem + s1.length, s2.data, s2.length * sizeof(char));
	mem[new_length] = 0;

	String new_str = unique_string_new_length(table, arena, mem, new_length, 0);
	if (new_str.data == mem)
	{
		char* newmem = arena_alloc(arena, (new_length + 1) * sizeof(char));
		memcpy(newmem, mem, (new_length + 1) * sizeof(char));
		new_str.data = newmem;
	}
	free(mem);
	return new_str;
}

int unique_string_equal(String s1, String s2)
{
	return (s1.data == s2.data) && (s1.length == s2.length);
}

String unique_string_substring(Hoht_Table* table, Light_Arena* arena, String s, int64_t index, int64_t length)
{
	if (index > 0 && index < s.length)
	{
		if (length >= s.length - index)
			length = s.length - index - 1;
		return unique_string_new_length(table, arena, s.data + index, length, 0);
	}
	return s;
}

String unique_string_uppercase(Hoht_Table* table, Light_Arena* arena, String s)
{
	char* mem = (char*)calloc(1, (s.length + 1) * sizeof(char));
	memcpy(mem, s.data, s.length * sizeof(char));
	mem[s.length] = 0;

	for (int i = 0; i < s.length; ++i)
	{
		char c = mem[i];
		if (c >= 'a' && c <= 'z')
			mem[i] = c - 'a' + 'A';
	}
	String result = unique_string_new_length(table, arena, mem, s.length, 0);
	if (result.data == mem)
	{
		char* newmem = arena_alloc(arena, (s.length + 1) * sizeof(char));
		memcpy(newmem, mem, (s.length + 1) * sizeof(char));
		result.data = newmem;
	}
	free(mem);
	return result;
}

String unique_string_lowercase(Hoht_Table* table, Light_Arena* arena, String s)
{
	char* mem = (char*)calloc(1, (s.length + 1) * sizeof(char));
	memcpy(mem, s.data, s.length * sizeof(char));
	mem[s.length] = 0;

	for (int i = 0; i < s.length; ++i)
	{
		char c = mem[i];
		if (c >= 'A' && c <= 'Z')
			mem[i] = c - 'A' + 'a';
	}
	String result = unique_string_new_length(table, arena, mem, s.length, 0);
	if (result.data == mem)
	{
		char* newmem = arena_alloc(arena, (s.length + 1) * sizeof(char));
		memcpy(newmem, mem, (s.length + 1) * sizeof(char));
		result.data = newmem;
	}
	free(mem);
	return result;
}

String unique_string_trim(Hoht_Table* table, Light_Arena* arena, String s)
{
	int64_t cbefore = 0;
	int64_t cafter = 0;

	for (int i = 0; i < s.length; ++i)
	{
		char c = s.data[i];

		if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\v')
			cbefore++;
		else
			break;
	}
	for (int64_t i = s.length - 1; i >= 0; --i)
	{
		char c = s.data[i];

		if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\v')
			cafter++;
		else
			break;
	}

	return unique_string_substring(table, arena, s, cbefore, s.length - cbefore - cafter);
}

int64_t string_index_of(String s, char c)
{
	int64_t result = -1;
	for (int i = 0; i < s.length; ++i)
		if (s.data[i] == c)
			return i;
	return result;
}

String unique_string_print(Hoht_Table* table, Light_Arena* arena, char* fmt, ...)
{
	va_list args;
	va_start(args, fmt);

	char buffer[256] = { 0 };
	size_t alloc_size = sizeof(buffer);
	int len = _vsnwprintf_s(buffer, alloc_size / sizeof(char), (alloc_size - 1) / sizeof(char) - 1, fmt, args);
	int reuse = 0;

	char* mem = buffer;

	while (len == -1)
	{
		alloc_size *= 2;
		mem = (char*)calloc(1, alloc_size);
		len = _vsnwprintf_s(mem, alloc_size / sizeof(char), (alloc_size - 1) / sizeof(char), fmt, args);
		reuse = 1;
		if (len == -1)
			free(mem);
	}

	va_end(args);

	String result = unique_string_new_length(table, arena, mem, len, 0);
	free(mem);

	return result;
}

int string_has_prefix(String prefix, String s)
{
	if (s.length < prefix.length)
		return 0;
	for (int i = 0; i < prefix.length; ++i)
	{
		if (prefix.data[i] != s.data[i])
			return 0;
	}
	return 1;
}

int string_has_prefix_char(char* prefix, String s)
{
	for (int i = 0; i < s.length && prefix[i] != 0; ++i)
	{
		if (prefix[i] != s.data[i])
			return 0;
	}
	return 1;
}

int string_equal(String s1, String s2)
{
	if (s1.length != s2.length)
		return 0;
	for (int i = 0; i < s1.length; ++i)
	{
		if (s1.data[i] != s2.data[i])
			return 0;
	}
	return 1;
}

int string_equal_char(char* s1, String s2)
{
	int i = 0;
	for (; i < s2.length && s1[i] != 0; ++i)
	{
		if (s1[i] != s2.data[i])
			return 0;
	}
	return (i == s2.length) && (s1[i] == 0);
}

String
ustr_new(char* str)
{
	return unique_string_new(&normal_string_table, string_arena, str);
}

String
ustr_new_len(char* str, int64_t len)
{
	return unique_string_new_length(&normal_string_table, string_arena, str, len, 1);
}

String
ustr_copy(String s)
{
	return ustr_new_len(s.data, s.length);
}

String
ustr_concat(String s1, String s2)
{
	return unique_string_concatenate(&normal_string_table, string_arena, s1, s2);
}

int
ustr_equal(String s1, String s2)
{
	return unique_string_equal(s1, s2);
}

String
ustr_substring(String s, int64_t index, int64_t length)
{
	return unique_string_substring(&normal_string_table, string_arena, s, index, length);
}

String
ustr_uppercase(String s)
{
	return unique_string_uppercase(&normal_string_table, string_arena, s);
}

String
ustr_lowercase(String s)
{
	return unique_string_lowercase(&normal_string_table, string_arena, s);
}

String
ustr_trim(String s)
{
	return unique_string_trim(&normal_string_table, string_arena, s);
}

int
str_has_prefix(String prefix, String s)
{
	return string_has_prefix(prefix, s);
}

int
str_has_prefix_char(char* prefix, String s)
{
	return string_has_prefix_char(prefix, s);
}

int
str_equal(String s1, String s2)
{
	return string_equal(s1, s2);
}

int
str_equal_char(char* s1, String s2)
{
	return string_equal_char(s1, s2);
}

// Temporary

String
tmp_str_new(char* str)
{
	return unique_string_new(&tmp_normal_string_table, tmp_string_arena, str);
}

String
tmp_str_new_len(char* str, int64_t len)
{
	return unique_string_new_length(&tmp_normal_string_table, tmp_string_arena, str, len, 1);
}

String
tmp_str_concat(String s1, String s2)
{
	return unique_string_concatenate(&tmp_normal_string_table, tmp_string_arena, s1, s2);
}

int
tmp_str_equal(String s1, String s2)
{
	return unique_string_equal(s1, s2);
}

String
tmp_str_substring(String s, int64_t index, int64_t length)
{
	return unique_string_substring(&tmp_normal_string_table, tmp_string_arena, s, index, length);
}

String
tmp_str_uppercase(String s)
{
	return unique_string_uppercase(&tmp_normal_string_table, tmp_string_arena, s);
}

String
tmp_str_lowercase(String s)
{
	return unique_string_lowercase(&tmp_normal_string_table, tmp_string_arena, s);
}

String
tmp_str_trim(String s)
{
	return unique_string_trim(&tmp_normal_string_table, tmp_string_arena, s);
}

String
tmp_str_new_c(char* str)
{
	size_t len = strlen(str);
	char* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(char));
	memcpy(res, str, len);
	res[len] = 0;
	return tmp_str_new_len(res, len);
}

String
tmp_str_new_len_c(char* str, int64_t len)
{
	char* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(char));
	memcpy(res, str, len);
	res[len] = 0;
	return tmp_str_new_len(res, len);
}

String
ustr_new_c(char* str)
{
	size_t len = strlen(str);
	wchar_t* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(char));
	memcpy(res, str, len);
	res[len] = 0;
	String result = unique_string_new_length(&normal_string_table, string_arena, res, len, 0);
	return result;
}

String
ustr_new_len_c(char* str, int64_t len)
{
	wchar_t* res = arena_alloc(tmp_string_arena, (len + 1) * sizeof(char));
	memcpy(res, str, len);
	res[len] = 0;
	String result = unique_string_new_length(&normal_string_table, string_arena, res, len, 0);
	return result;
}