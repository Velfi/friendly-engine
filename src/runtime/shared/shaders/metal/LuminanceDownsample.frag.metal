// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float2 uv;
};

float logLuminanceAt(
    metal::float2 uv,
    metal::texture2d<float, metal::access::sample> hdr_color,
    metal::sampler hdr_sampler
) {
    metal::float4 _e4 = hdr_color.sample(hdr_sampler, uv, metal::level(0.0));
    metal::float3 color = metal::max(_e4.xyz, metal::float3(0.0));
    float luma = metal::dot(color, metal::float3(0.2126, 0.7152, 0.0722));
    return metal::log2(metal::max(luma, 0.0001));
}

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct main_Output {
    float member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, metal::texture2d<float, metal::access::sample> hdr_color [[user(fake0)]]
, metal::sampler hdr_sampler [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv };
    float sum = 0.0;
    uint y = 0u;
    uint x = {};
    uint2 loop_bound = uint2(4294967295u);
    while(true) {
        if (metal::all(loop_bound == uint2(0u))) { break; }
        loop_bound -= uint2(loop_bound.y == 0u, 1u);
        uint _e5 = y;
        if (_e5 >= 16u) {
            break;
        }
        x = 0u;
        uint2 loop_bound_1 = uint2(4294967295u);
        while(true) {
            if (metal::all(loop_bound_1 == uint2(0u))) { break; }
            loop_bound_1 -= uint2(loop_bound_1.y == 0u, 1u);
            uint _e10 = x;
            if (_e10 >= 16u) {
                break;
            }
            uint _e13 = x;
            uint _e19 = y;
            metal::float2 uv_1 = metal::float2((static_cast<float>(_e13) + 0.5) / 16.0, (static_cast<float>(_e19) + 0.5) / 16.0);
            float _e26 = sum;
            float _e27 = logLuminanceAt(uv_1, hdr_color, hdr_sampler);
            sum = _e26 + _e27;
            uint _e29 = x;
            x = _e29 + 1u;
        }
        uint _e32 = y;
        y = _e32 + 1u;
    }
    float _e35 = sum;
    return main_Output { _e35 / 256.0 };
}
