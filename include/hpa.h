#ifndef HO_PARSE_UTILS_H
#define HO_PARSE_UTILS_H
#include <stdint.h>

int64_t  hpa_parse_int64(const char** stream);
int32_t  hpa_parse_int32(const char** stream);
int16_t  hpa_parse_int16(const char** stream);
int8_t   hpa_parse_int8(const char** stream);
int64_t  hpa_parse_int64_length(const char** stream, int length);
int32_t  hpa_parse_int32_length(const char** stream, int length);
int16_t  hpa_parse_int16_length(const char** stream, int length);
int8_t   hpa_parse_int8_length(const char** stream, int length);
uint64_t hpa_parse_uint64(const char** stream);
uint32_t hpa_parse_uint32(const char** stream);
uint16_t hpa_parse_uint16(const char** stream);
uint8_t  hpa_parse_uint8(const char** stream);
uint64_t hpa_parse_uint64_wide(const wchar_t** stream);
uint32_t hpa_parse_uint32_wide(const wchar_t** stream);
uint16_t hpa_parse_uint16_wide(const wchar_t** stream);
uint8_t  hpa_parse_uint8_wide(const wchar_t** stream);
uint64_t hpa_parse_uint64_length(const char** stream, int length);
uint64_t hpa_parse_uint64_hex(const char** stream);
uint64_t hpa_parse_uint64_prefixed_hex(const char** stream);
uint64_t hpa_parse_uint64_hex_length(const char** stream, int length);
uint64_t hpa_parse_uint64_prefixed_hex_length(const char** stream, int length);
double   hpa_parse_float64(const char** stream);
float    hpa_parse_float32(const char** stream);
double   hpa_parse_float64_length(const char** stream, int length);
float    hpa_parse_float32_length(const char** stream, int length);
int      hpa_parse_identifier(const char* stream);
int      hpa_parse_escape_sequence(const char** stream, uint32_t* unicode);
int      hpa_parse_whitespace(const char** stream);
int      hpa_parse_until_eol(const char** stream);
int      hpa_parse_until_eol_length(const char** stream, int length);
int      hpa_parse_keyword(const char** stream, const char* keyword);
int      hpa_parse_keyword_length(const char** stream, int length, const char* keyword);

#ifdef HPA_IMPLEMENTATION

static int
hpa_is_number(char c)
{
	return (c >= '0') && (c <= '9');
}

static int
hpa_is_number_wide(wchar_t c)
{
	return (c >= '0') && (c <= '9');
}

static int
hpa_is_alphanum(char c)
{
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static int
hpa_hex_to_num(char c)
{
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	return c - '0';
}

static int
hpa_is_hexdigit(char c)
{
	return hpa_is_number(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static bool
is_whitespace(char c)
{
	return (c == ' ' || c == '\r' || c == '\t' || c == '\b' || c == '\f' || c == '\v' || c == '\n');
}

int
hpa_parse_whitespace(const char** stream)
{
	const char* at = *stream;
	while (is_whitespace(*at)) at++;
	int len = (int)(at - *stream);
	*stream = at;
	return len;
}

// Parses a 64bit signed integer value given a stream;
// advances the stream to the number of characters parsed;
// returns 0 in case the stream is invalid, no error.
int64_t
hpa_parse_int64(const char** stream)
{
	int64_t sign = 1;
	const char* at = *stream;
	if (*at == '-')
	{
		sign = -1;
		at++;
	}

	int64_t result = 0;
	while (hpa_is_number(*at))
	{
		if (result != 0)
			result *= 10;

		result += (*at - 0x30);
		at++;
	}
	*stream = at;
	return result * sign;
}

int32_t
hpa_parse_int32(const char** stream)
{
	int64_t result = hpa_parse_int64(stream);
	return (int32_t)result;
}

int16_t
hpa_parse_int16(const char** stream)
{
	int64_t result = hpa_parse_int64(stream);
	return (int16_t)result;
}

int8_t
hpa_parse_int8(const char** stream)
{
	int64_t result = hpa_parse_int64(stream);
	return (int8_t)result;
}

// Parses a 64bit signed integer value given a stream and length;
// returns 0 in case the stream is invalid, no error.
int64_t
hpa_parse_int64_length(const char** stream, int length)
{
	int64_t sign = 1;
	const char* at = *stream;
	if (*at == '-')
	{
		sign = -1;
		at++;
		length--;
	}

	int64_t result = 0;
	for (int i = 0; i < length; ++i)
	{
		if (*at && hpa_is_number(*at))
		{
			if (result != 0)
				result *= 10;

			result += (*at - 0x30);
			at++;
		}
		else
		{
			return 0;
		}
	}

	*stream = at;
	return result * sign;
}

int32_t
hpa_parse_int32_length(const char** stream, int length)
{
	int64_t result = hpa_parse_int64_length(stream, length);
	return (int32_t)result;
}

int16_t
hpa_parse_int16_length(const char** stream, int length)
{
	int64_t result = hpa_parse_int64_length(stream, length);
	return (int16_t)result;
}

int8_t
hpa_parse_int8_length(const char** stream, int length)
{
	int64_t result = hpa_parse_int64_length(stream, length);
	return (int8_t)result;
}

// Parses a 64bit unsigned integer value given a stream;
// advances the stream to the number of characters parsed;
// returns 0 in case the stream is invalid, no error.
uint64_t
hpa_parse_uint64(const char** stream)
{
	const char* at = *stream;

	uint64_t result = 0;
	while (hpa_is_number(*at))
	{
		if (result != 0)
			result *= 10;

		result += (*at - 0x30);
		at++;
	}
	*stream = at;
	return result;
}

uint32_t
hpa_parse_uint32(const char** stream)
{
	uint32_t result = (uint32_t)hpa_parse_uint64(stream);
	return (uint32_t)result;
}

uint16_t
hpa_parse_uint16(const char** stream)
{
	uint16_t result = (uint16_t)hpa_parse_uint64(stream);
	return (uint16_t)result;
}

uint8_t
hpa_parse_uint8(const char** stream)
{
	uint8_t result = (uint8_t)hpa_parse_uint64(stream);
	return (uint8_t)result;
}

// Parses a 64bit unsigned integer value given a stream;
// advances the stream to the number of characters parsed;
// returns 0 in case the stream is invalid, no error.
uint64_t
hpa_parse_uint64_wide(const wchar_t** stream)
{
	const wchar_t* at = *stream;

	uint64_t result = 0;
	while (hpa_is_number_wide(*at))
	{
		if (result != 0)
			result *= 10;

		result += (*at - 0x30);
		at++;
	}
	*stream = at;
	return result;
}

uint32_t
hpa_parse_uint32_wide(const wchar_t** stream)
{
	uint32_t result = (uint32_t)hpa_parse_uint64_wide(stream);
	return (uint32_t)result;
}

uint16_t
hpa_parse_uint16_wide(const wchar_t** stream)
{
	uint16_t result = (uint16_t)hpa_parse_uint64_wide(stream);
	return (uint16_t)result;
}

uint8_t
hpa_parse_uint8_wide(const wchar_t** stream)
{
	uint8_t result = (uint8_t)hpa_parse_uint64_wide(stream);
	return (uint8_t)result;
}

// Parses a 64bit unsigned integer value given a stream and length;
// returns 0 in case the stream is invalid, no error.
uint64_t
hpa_parse_uint64_length(const char** stream, int length)
{
	const char* at = *stream;

	uint64_t result = 0;
	for (int i = 0; i < length; ++i)
	{
		if (*at && hpa_is_number(*at))
		{
			if (result != 0)
				result *= 10;

			result += (*at - 0x30);
			at++;
		}
		else
		{
			return 0;
		}
	}

	*stream = at;
	return result;
}

// Parses a 64bit unsigned integer value given a stream
// encoded in hexadecimal;
// advances the stream to the number of characters parsed;
// returns 0 in case the stream is invalid, no error.
uint64_t
hpa_parse_uint64_hex(const char** stream)
{
	const char* at = *stream;

	uint64_t result = 0;
	while (hpa_is_hexdigit(*at))
	{
		if (result != 0)
			result *= 16;

		result += hpa_hex_to_num(*at);
		at++;
	}
	*stream = at;
	return result;
}

uint64_t
hpa_parse_uint64_prefixed_hex(const char** stream)
{
	const char* at = *stream;
	if (*at && at[0] == '0' && at[1] == 'x')
	{
		at += 2;
	}
	else
	{
		return 0;
	}
	*stream = at;
	return hpa_parse_uint64_hex(stream);
}

// Parses a 64bit unsigned integer value given a stream 
// encoded in hexadecimal and length;
// returns 0 in case the stream is invalid, no error.
uint64_t
hpa_parse_uint64_hex_length(const char** stream, int length)
{
	const char* at = *stream;

	uint64_t result = 0;
	for (int i = 0; i < length; ++i)
	{
		if (*at && hpa_is_hexdigit(*at))
		{
			if (result != 0)
				result *= 16;

			result += hpa_hex_to_num(*at);
			at++;
		}
		else
		{
			return 0;
		}
	}

	*stream = at;
	return result;
}

uint64_t
hpa_parse_uint64_prefixed_hex_length(const char** stream, int length)
{
	const char* at = *stream;
	if (*at && at[0] == '0' && at[1] == 'x' && length > 2)
	{
		at += 2;
		length -= 2;
	}
	else
	{
		return 0;
	}
	*stream = at;
	return hpa_parse_uint64_hex_length(stream, length);
}

static double hpa_float64_exponent_table[] = {
	1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10,
	1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20,
	1e21, 1e22, 1e23, 1e24, 1e25, 1e26, 1e27, 1e28, 1e29, 1e30,
	1e31, 1e32, 1e33, 1e34, 1e35, 1e36, 1e37, 1e38, 1e39, 1e40,
	1e41, 1e42, 1e43, 1e44, 1e45, 1e46, 1e47, 1e48, 1e49, 1e50,
	1e51, 1e52, 1e53, 1e54, 1e55, 1e56, 1e57, 1e58, 1e59, 1e60,
	1e61, 1e62, 1e63, 1e64, 1e65, 1e66, 1e67, 1e68, 1e69, 1e70,
	1e71, 1e72, 1e73, 1e74, 1e75, 1e76, 1e77, 1e78, 1e79, 1e80,
	1e81, 1e82, 1e83, 1e84, 1e85, 1e86, 1e87, 1e88, 1e89, 1e90,
	1e91, 1e92, 1e93, 1e94, 1e95, 1e96, 1e97, 1e98, 1e99, 1e100,
	1e101, 1e102, 1e103, 1e104, 1e105, 1e106, 1e107, 1e108, 1e109, 1e110,
	1e111, 1e112, 1e113, 1e114, 1e115, 1e116, 1e117, 1e118, 1e119, 1e120,
	1e121, 1e122, 1e123, 1e124, 1e125, 1e126, 1e127, 1e128, 1e129, 1e130,
	1e131, 1e132, 1e133, 1e134, 1e135, 1e136, 1e137, 1e138, 1e139, 1e140,
	1e141, 1e142, 1e143, 1e144, 1e145, 1e146, 1e147, 1e148, 1e149, 1e150,
	1e151, 1e152, 1e153, 1e154, 1e155, 1e156, 1e157, 1e158, 1e159, 1e160,
	1e161, 1e162, 1e163, 1e164, 1e165, 1e166, 1e167, 1e168, 1e169, 1e170,
	1e171, 1e172, 1e173, 1e174, 1e175, 1e176, 1e177, 1e178, 1e179, 1e180,
	1e181, 1e182, 1e183, 1e184, 1e185, 1e186, 1e187, 1e188, 1e189, 1e190,
	1e191, 1e192, 1e193, 1e194, 1e195, 1e196, 1e197, 1e198, 1e199, 1e200,
	1e201, 1e202, 1e203, 1e204, 1e205, 1e206, 1e207, 1e208, 1e209, 1e210,
	1e211, 1e212, 1e213, 1e214, 1e215, 1e216, 1e217, 1e218, 1e219, 1e220,
	1e221, 1e222, 1e223, 1e224, 1e225, 1e226, 1e227, 1e228, 1e229, 1e230,
	1e231, 1e232, 1e233, 1e234, 1e235, 1e236, 1e237, 1e238, 1e239, 1e240,
	1e241, 1e242, 1e243, 1e244, 1e245, 1e246, 1e247, 1e248, 1e249, 1e250,
	1e251, 1e252, 1e253, 1e254, 1e255, 1e256, 1e257, 1e258, 1e259, 1e260,
	1e261, 1e262, 1e263, 1e264, 1e265, 1e266, 1e267, 1e268, 1e269, 1e270,
	1e271, 1e272, 1e273, 1e274, 1e275, 1e276, 1e277, 1e278, 1e279, 1e280,
	1e281, 1e282, 1e283, 1e284, 1e285, 1e286, 1e287, 1e288, 1e289, 1e290,
	1e291, 1e292, 1e293, 1e294, 1e295, 1e296, 1e297, 1e298, 1e299, 1e300,
	1e301, 1e302, 1e303, 1e304, 1e305, 1e306, 1e307, 1e308
};
// Parses a 64bit floating point number encoded in the C format;
// Advances the stream by the number of bytes parsed. 
// If the stream is invalid, does not error out, just returns 0.
double
hpa_parse_float64(const char** stream)
{
	const char* at = *stream;
	double result = 0.0;

	double sign = 1.0;
	double int_part = 0.0;
	if (*at == '-')
	{
		sign = -1.0;
		at++;
	}

	int count = 0;
	while (hpa_is_number(*at))
	{
		if (count > 0)
			int_part *= 10.0;

		int_part += ((double)(*at - 0x30));
		at++;
		count++;
	}

	result = int_part * sign;
	
	if (*at == '.')
	{
		at++;
		double fractional = 0.0;
		double tenth = 10.0;
		while (hpa_is_number(*at))
		{
			fractional += (double)(*at - 0x30) / tenth;
			at++;
			tenth *= 10.0;
		}
		result += fractional;
	}

	if (*at == 'e' || *at == 'E')
	{
		at++;
		int32_t exponent = hpa_parse_int32(&at);
		if (exponent > 308 && exponent < -308)
		{
			return 0.0;
		}
		else
		{
			if (exponent >= 0)
				result = result * hpa_float64_exponent_table[exponent];
			else
				result = result / hpa_float64_exponent_table[-exponent];
		}
	}
	*stream = at;
	return result;
}

double
hpa_parse_float64_length(const char** stream, int length)
{
	const char* at = *stream;
	double result = 0.0;

	double sign = 1.0;
	double int_part = 0.0;
	if (*at == '-')
	{
		sign = -1.0;
		at++;
		length--;
	}

	int count = 0;
	while (hpa_is_number(*at) && length > 0)
	{
		if (count > 0)
			int_part *= 10.0;

		int_part += ((double)(*at - 0x30));
		at++;
		count++;
		length--;
	}

	result = int_part * sign;

	if (length == 0)
		return result;

	if (*at == '.')
	{
		at++;
		length--;
		double fractional = 0.0;
		double tenth = 10.0;
		while (hpa_is_number(*at) && length > 0)
		{
			fractional += (double)(*at - 0x30) / tenth;
			at++;
			length--;
			tenth *= 10.0;
		}
		result += fractional;
	}

	if (length == 0)
		return result;

	if (*at == 'e' || *at == 'E')
	{
		at++;
		length--;
		int32_t exponent = hpa_parse_int32_length(&at, length);
		if (exponent > 308 && exponent < -308)
		{
			return 0.0;
		}
		else
		{
			if (exponent >= 0)
				result = result * hpa_float64_exponent_table[exponent];
			else
				result = result / hpa_float64_exponent_table[-exponent];
		}
	}
	*stream = at;
	return result;
}

static float hpa_float32_exponent_table[] = {
	1e0f, 1e1f, 1e2f, 1e3f, 1e4f, 1e5f, 1e6f, 1e7f, 1e8f, 1e9f, 1e10f,
	1e11f, 1e12f, 1e13f, 1e14f, 1e15f, 1e16f, 1e17f, 1e18f, 1e19f, 1e20f,
	1e21f, 1e22f, 1e23f, 1e24f, 1e25f, 1e26f, 1e27f, 1e28f, 1e29f, 1e30f,
	1e31f, 1e32f, 1e33f, 1e34f, 1e35f, 1e36f, 1e37f, 1e38f
};
// Parses a 32bit floating point number encoded in the C format;
// Advances the stream by the number of bytes parsed. 
// If the stream is invalid, does not error out, just returns 0.
float
hpa_parse_float32(const char** stream)
{
	const char* at = *stream;
	float result = 0.0f;

	float sign = 1.0f;
	float int_part = 0.0f;
	if (*at == '-')
	{
		sign = -1.0f;
		at++;
	}

	int count = 0;
	while (hpa_is_number(*at))
	{
		if (count > 0)
			int_part *= 10.0f;

		int_part += ((float)(*at - 0x30));
		at++;
		count++;
	}

	result = int_part * sign;

	if (*at == '.')
	{
		at++;
		float fractional = 0.0f;
		float tenth = 10.0f;
		while (hpa_is_number(*at))
		{
			fractional += (float)(*at - 0x30) / tenth;
			at++;
			tenth *= 10.0f;
		}
		result += fractional;
	}

	if (*at == 'e' || *at == 'E')
	{
		at++;
		int32_t exponent = hpa_parse_int32(&at);
		if (exponent > 38 && exponent < -38)
		{
			return 0.0f;
		}
		else
		{
			if (exponent >= 0)
				result = result * hpa_float32_exponent_table[exponent];
			else
				result = result / hpa_float32_exponent_table[-exponent];
		}
	}
	*stream = at;
	return result;
}

float
hpa_parse_float32_length(const char** stream, int length)
{
	const char* at = *stream;
	float result = 0.0f;

	float sign = 1.0f;
	float int_part = 0.0f;
	if (*at == '-')
	{
		sign = -1.0f;
		at++;
		length--;
	}

	int count = 0;
	while (hpa_is_number(*at) && length > 0)
	{
		if (count > 0)
			int_part *= 10.0f;

		int_part += ((float)(*at - 0x30));
		at++;
		count++;
		length--;
	}

	result = int_part * sign;

	if (length == 0)
		return result;

	if (*at == '.')
	{
		at++;
		length--;
		float fractional = 0.0f;
		float tenth = 10.0f;
		while (hpa_is_number(*at) && length > 0)
		{
			fractional += (float)(*at - 0x30) / tenth;
			at++;
			length--;
			tenth *= 10.0f;
		}
		result += fractional;
	}

	if (length == 0)
		return result;

	if (*at == 'e' || *at == 'E')
	{
		at++;
		length--;
		int32_t exponent = hpa_parse_int32_length(&at, length);
		if (exponent > 38 && exponent < -38)
		{
			return 0.0f;
		}
		else
		{
			if (exponent >= 0)
				result = result * hpa_float32_exponent_table[exponent];
			else
				result = result / hpa_float32_exponent_table[-exponent];
		}
	}

	return result;
}

// Parses an identifier in the C style. Formed by alphanumeric 
// characters and underlines.
int
hpa_parse_identifier(const char* stream)
{
	const char* at = stream;
	if (at && !hpa_is_number(*at))
	{
		while (hpa_is_alphanum(*at) || *at == '_')
		{
			at++;
		}
	}
	return (int)(at - stream);
}

// Parses an escape sequence in the format with backslash
// return value is the length of the unicode point parsed;
// The codepoint is returned by reference and the stream
// is advanced by the amount of bytes parsed.
int
hpa_parse_escape_sequence(const char** stream, uint32_t* codepoint)
{
	int length = 1;
	const char* at = *stream;
	if (*at != '\\') return 0;
	at++;

	switch (*at)
	{
		case 'a':  *codepoint = '\a'; break;
		case 'b':  *codepoint = '\b'; break;
		case 'f':  *codepoint = '\f'; break;
		case 'n':  *codepoint = '\n'; break;
		case 'r':  *codepoint = '\r'; break;
		case 't':  *codepoint = '\t'; break;
		case 'v':  *codepoint = '\v'; break;
		case '\\': *codepoint = '\\'; break;
		case '\'': *codepoint = '\''; break;
		case '"':  *codepoint = '\"'; break;
		case 'x': {
			at++;
			if (hpa_is_hexdigit(at[0]) && hpa_is_hexdigit(at[1]))
			{
				*codepoint = (hpa_hex_to_num(at[0]) * 16) + hpa_hex_to_num(at[1]);
				at += 2;
			}
			else
				return 0;
		} break;
		case 'u': {
			at++;
			if (hpa_is_hexdigit(at[0]) && hpa_is_hexdigit(at[1]) && hpa_is_hexdigit(at[2]) && hpa_is_hexdigit(at[3]))
			{
				*codepoint = (hpa_hex_to_num(at[0]) << 12) | (hpa_hex_to_num(at[1]) << 8) | (hpa_hex_to_num(at[2]) << 4) | (hpa_hex_to_num(at[3]));
				at += 4;
				length = 2;
			}
			else
				return 0;
		} break;
		case 'U': {
			at++;
			if (hpa_is_hexdigit(at[0]) && hpa_is_hexdigit(at[1]) && hpa_is_hexdigit(at[2]) && hpa_is_hexdigit(at[3]) && 
				hpa_is_hexdigit(at[4]) && hpa_is_hexdigit(at[5]) && hpa_is_hexdigit(at[6]) && hpa_is_hexdigit(at[7]))
			{
				*codepoint = (hpa_hex_to_num(at[0]) << 28) | (hpa_hex_to_num(at[1]) << 24) | (hpa_hex_to_num(at[2]) << 20) | (hpa_hex_to_num(at[3]) << 16) |
					       (hpa_hex_to_num(at[4]) << 12) | (hpa_hex_to_num(at[5]) << 8)  | (hpa_hex_to_num(at[6]) << 4)  | (hpa_hex_to_num(at[7]));
				at += 8;
				length = 4;
			}
			else
				return 0;
		} break;
		default: {
			length = 0;
		} break;
	}

	*stream = at;
	return length;
}

// Parses any characters until it finds '\n', advacing the stream.
// Returns the number of characters read.
int
hpa_parse_until_eol(const char** stream)
{
	const char* at = *stream;

	while (*at++ != '\n');

	int length = (int)(at - *stream);
	*stream = at;
	return length;
}

// Parses any characters until it finds '\n' or reaches the
// maximum length specified, advacing the stream.
// Returns the number of characters read.
int
hpa_parse_until_eol_length(const char** stream, int length)
{
	const char* at = *stream;

	if (length > 0)
	{
		while (length > 0 && *at++ != '\n') length--;
	}

	int read_length = (int)(at - *stream);
	*stream = at;
	return read_length;
}

// Parses a keyword, returns the length of they keyword in
// case it is valid and advances the stream, otherwise
// it returns 0 and the stream is preserved.
int
hpa_parse_keyword(const char** stream, const char* keyword)
{
	const char* at = *stream;
	while (*keyword && *keyword == *at)
	{
		keyword++;
		at++;
	}

	int length = (int)(at - *stream);
	if (*keyword == 0)
	{
		*stream = at;
		return length;
	}

	return 0;
}

// Parses a keyword until the given stream length, returns 
// the length of they keyword in case it is valid and advances 
// the stream, otherwise it returns 0 and the stream is preserved.
int
hpa_parse_keyword_length(const char** stream, int length, const char* keyword)
{
	const char* at = *stream;
	while (length > 0 && *keyword && *keyword == *at)
	{
		keyword++;
		at++;
		length--;
	}

	int read_length = (int)(at - *stream);
	if (*keyword == 0)
	{
		*stream = at;
		return read_length;
	}

	return 0;
}

#endif // HPA_IMPLEMENTATION
#endif // HO_PARSE_UTILS_H