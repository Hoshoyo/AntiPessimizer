#pragma once
#include <gm.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <hpa.h>
#include <windows.h>

typedef u64 datetime_s;
typedef r64 datetime_f;
typedef datetime_f TDateTime;
typedef u64 unix_ms_date;

typedef struct {
    s32 year;
    s32 month;
    s32 day;
    s32 hour;
    s32 minute;
    s32 second;
    s32 millisecond;
} DateTime;

inline void
datetime_ms_to_string(unix_ms_date time, _Out_ char* strTime, size_t size) {
    u64 ms = time % 1000;
    time /= 1000;
	struct tm* tminfo = localtime(&time);
    if (tminfo)
    {
        size_t len = strftime(strTime, size, "%Y-%m-%d %H:%M:%S", tminfo);
        sprintf(strTime + len, ".%03lld", ms);
    }
    else
        memset(strTime, 0, size);
}

inline void
date_to_string(datetime_s time, _Out_ char* strTime, size_t size) {
    struct tm* tminfo = localtime(&time);
    if (tminfo)
        strftime(strTime, size, "%Y-%m-%d", tminfo);
    else
        memset(strTime, 0, size);
}

inline s32
datetime_to_string_wide(datetime_s time, wchar_t* str_time, size_t size) {
    struct tm* tminfo = localtime(&time);
    if (tminfo)
        return (s32)wcsftime(str_time, size, L"%d/%m/%Y %H:%M:%S", tminfo);
    else
        memset(str_time, 0, size);
    return 0;
}

inline s32
datetime_to_string(datetime_s time, char* str_time, size_t size) {
    struct tm* tminfo = localtime(&time);
    if (tminfo)
        return (s32)strftime(str_time, size, "%d/%m/%Y %H:%M:%S", tminfo);
    else
        memset(str_time, 0, size);
    return 0;
}

inline datetime_s
convert_to_unix_datetime(s32 year, s32 month, s32 day, s32 hour, s32 minute, s32 second) {
    struct tm t = {
        .tm_sec = second,
        .tm_min = minute,
        .tm_hour = hour,
        .tm_mday = day,
        .tm_mon = month - 1,
        .tm_year = year - 1900,
        .tm_isdst = -1,
    };
    time_t epoch = mktime(&t);
    return epoch;
}

inline datetime_s
date_of_today() {
    SYSTEMTIME systime = { 0 };
    GetSystemTime(&systime);
    return convert_to_unix_datetime(systime.wYear, systime.wMonth, systime.wDay, 0, 0, 0);
}

inline void
datetime_now(s32* year, s32* month, s32* day, s32* hour, s32* minute, s32* sec, s32* ms) {
    SYSTEMTIME systime = { 0 };
    GetSystemTime(&systime);
    if (year) *year = systime.wYear;
    if (month) *month = systime.wMonth;
    if (day) *day = systime.wDay;
    if (hour) *hour = systime.wHour;
    if (minute) *minute = systime.wMinute;
    if (sec) *sec = systime.wSecond;
    if (ms) *ms = systime.wMilliseconds;
}

inline datetime_s
last_business_day() {
    SYSTEMTIME systime = { 0 };
    GetSystemTime(&systime);
    datetime_s result = convert_to_unix_datetime(systime.wYear, systime.wMonth, systime.wDay, 0, 0, 0);
    if (systime.wDayOfWeek == 0) {
        // Sunday
        return (result - 2 * 60 * 60 * 24);
    } else if(systime.wDayOfWeek == 6) {
        // Saturday
        return (result - 60 * 60 * 24);
    }
    return result;
}

inline datetime_s
string_to_date(char* strDate) {
    char* token = strtok(strDate, "/");
    s32 month = 0;
    s32 year = 0;
    s32 day = 0;
    if (token) {
        month = atoi(token);
        token = strtok(NULL, "/");
        day = atoi(token);
        token = strtok(NULL, "/");
        year = atoi(token);
    }
    return convert_to_unix_datetime(year, month, day, 0, 0, 0);
}

inline unix_ms_date
string_to_datetime_wide(wchar_t* date) {
    wchar_t* at = date;
    if (!(*at >= '0' && *at <= '9'))
        return (unix_ms_date){ 0 };
    u32 day = hpa_parse_uint32_wide(&at);
    if (*at++ != '/')
        return (unix_ms_date) { 0 };
    u32 month = hpa_parse_uint32_wide(&at);
    if (*at++ != '/')
        return (unix_ms_date) { 0 };
    u32 year = hpa_parse_uint32_wide(&at);

    u32 hour = 0;
    u32 minute = 0;
    u32 second = 0;
    u32 millisecond = 0;
    if (*at++ == ' ')
    {
        hour = hpa_parse_uint32_wide(&at);
        if (*at++ != ':')
            goto end_datetime_wide;
        minute = hpa_parse_uint32_wide(&at);
        if (*at++ != ':')
            goto end_datetime_wide;
        second = hpa_parse_uint32_wide(&at);
        if (*at++ != '.')
            goto end_datetime_wide;
        millisecond = hpa_parse_uint32_wide(&at);
    }
    datetime_s unix = 0;
end_datetime_wide:
    unix = convert_to_unix_datetime(year, month, day, hour, minute, second);
    unix *= 1000;
    unix += (u64)millisecond;

    return unix;
}

typedef struct {
    int time;
    int date;
} Timestamp;

#define FM_SECS_PER_DAY 86400000
#define DateDelta 693594
#define D1 (365)
#define D4 (D1 * 4 + 1)
#define D100 (D4 * 25 - 1)
#define D400 (D100 * 4 + 1)
#define HoursPerDay 24
#define MinsPerHour 60
#define SecsPerMin 60
#define MSecsPerSec 1000

static Timestamp 
datetime_to_timestamp(r64 datetime)
{
    Timestamp result = { 0 };
    s64 ltemp = (s64)round(datetime * FM_SECS_PER_DAY);
    s64 ltemp2 = (ltemp / FM_SECS_PER_DAY);
    result.date = (s32)(DateDelta + ltemp2);
    result.time = (abs((s32)ltemp) % FM_SECS_PER_DAY);

    return result;
}

static void 
divmod(int dividend, int divisor, int* result, int* remainder)
{
    *result = dividend / divisor;
    *remainder = dividend % divisor;
}


static bool 
is_leap_year(int year)
{
    return (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));
}

static int MonthDays[2][12] =
{
    { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 },
    { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
};

static bool 
decode_date_fully(const double datetime, int* year, int* month, int* day, int* day_of_week)
{
    int y, m, d, i;

    bool result = 1;
    int t = datetime_to_timestamp(datetime).date;
    if (t <= 0)
    {
        *year = 0;
        *month = 0;
        *day = 0;
        *day_of_week = 0;
        result = 0;
    }
    else
    {
        *day_of_week = t % 7 + 1;
        t--;
        y = 1;
        while (t > D400)
        {
            t -= D400;
            y += 400;
        }
        divmod(t, D100, &i, &d);
        if (i == 4)
        {
            i--;
            d += D100;
        }
        y += i * 100;
        divmod(d, D4, &i, &d);
        y += (i * 4);
        divmod(d, D1, &i, &d);
        if (i == 4)
        {
            i--;
            d += D1;
        }
        y += i;
        result = is_leap_year(y);
        int* pdtable = (int*)MonthDays[result];
        m = 1;
        while (1)
        {
            i = pdtable[m];
            if (d < i)
                break;
            d -= i;
            m++;
        }
        *year = y;
        *month = m;
        *day = d + 1;
    }
    return result;
}

static void 
decode_time(const double datetime, int* hour, int* min, int* sec, int* msec)
{
    int min_count, msec_count;
    divmod(datetime_to_timestamp(datetime).time, SecsPerMin * MSecsPerSec, &min_count, &msec_count);
    divmod(min_count, MinsPerHour, hour, min);
    divmod(msec_count, MSecsPerSec, sec, msec);
}

static void 
decode_date_time(const double datetime, int* year, int* month, int* day, int* dow, int* hour, int* min, int* sec, int* ms)
{
    decode_date_fully(datetime, year, month, day, dow);
    decode_time(datetime, hour, min, sec, ms);
}