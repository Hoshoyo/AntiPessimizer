#pragma once
#include "imgui.h"
#include <math.h>

// Color manipulation
typedef struct {
    float L;
    float a;
    float b;
} ColorOKLab;

// Functions from https://bottosson.github.io/posts/oklab/
inline ColorOKLab
linear_srgb_to_oklab(ImVec4 c)
{
    float l = 0.4122214708f * c.x + 0.5363325363f * c.y + 0.0514459929f * c.z;
    float m = 0.2119034982f * c.x + 0.6806995451f * c.y + 0.1073969566f * c.z;
    float s = 0.0883024619f * c.x + 0.2817188376f * c.y + 0.6299787005f * c.z;

    float l_ = cbrtf(l);
    float m_ = cbrtf(m);
    float s_ = cbrtf(s);

    return {
        0.2104542553f * l_ + 0.7936177850f * m_ - 0.0040720468f * s_,
        1.9779984951f * l_ - 2.4285922050f * m_ + 0.4505937099f * s_,
        0.0259040371f * l_ + 0.7827717662f * m_ - 0.8086757660f * s_,
    };
}

inline ImVec4
oklab_to_linear_srgb(ColorOKLab c)
{
    float l_ = c.L + 0.3963377774f * c.a + 0.2158037573f * c.b;
    float m_ = c.L - 0.1055613458f * c.a - 0.0638541728f * c.b;
    float s_ = c.L - 0.0894841775f * c.a - 1.2914855480f * c.b;

    float l = l_ * l_ * l_;
    float m = m_ * m_ * m_;
    float s = s_ * s_ * s_;

    return {
        +4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s,
        1.0f
    };
}

inline float
lerp(float v0, float v1, float t) {
    return v0 + t * (v1 - v0);
}

inline ImVec4
interpolate_color(ImVec4 cl1, ImVec4 cl2, float factor)
{
    ColorOKLab labcl1 = linear_srgb_to_oklab(cl1);
    ColorOKLab labcl2 = linear_srgb_to_oklab(cl2);

    float a = lerp(labcl1.a, labcl2.a, factor);
    float b = lerp(labcl1.b, labcl2.b, 1 - factor);
    float L = labcl1.L;

    ColorOKLab resultlab = { L, a, b };
    return oklab_to_linear_srgb(resultlab);
}