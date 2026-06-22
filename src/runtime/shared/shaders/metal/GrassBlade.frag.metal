// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float4 color;
    metal::float3 world_normal;
    metal::float2 blade_uv;
    char _pad3[8];
};

metal::float3 safeNormalize3_(
    metal::float3 value,
    metal::float3 fallback
) {
    float len_sq = metal::dot(value, value);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return value * metal::rsqrt(len_sq);
}

struct main_Input {
    metal::float4 color [[user(loc0), center_perspective]];
    metal::float3 world_normal [[user(loc1), center_perspective]];
    metal::float2 blade_uv [[user(loc2), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
) {
    const FragmentInput input = { varyings.color, varyings.world_normal, varyings.blade_uv };
    metal::float3 _e6 = safeNormalize3_(input.world_normal, metal::float3(0.0, 1.0, 0.0));
    metal::float3 _e15 = safeNormalize3_(metal::float3(0.34, 0.88, 0.25), metal::float3(0.0, 1.0, 0.0));
    float wrap = metal::max((metal::dot(_e6, _e15) * 0.5) + 0.5, 0.0);
    float vertical = metal::smoothstep(0.0, 1.0, input.blade_uv.y);
    float midrib = 1.0 - metal::abs((input.blade_uv.x * 2.0) - 1.0);
    float painterly = ((0.72 + (wrap * 0.32)) + (midrib * 0.06)) + (vertical * 0.05);
    float tip_alpha = metal::smoothstep(0.02, 0.18, 1.0 - input.blade_uv.y);
    float alpha = input.color.w * tip_alpha;
    return main_Output { metal::float4(input.color.xyz * painterly, alpha) };
}
