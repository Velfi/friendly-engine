// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float2 uv;
    char _pad1[8];
    metal::float4 color;
};

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
    metal::float4 color [[user(loc1), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, metal::texture2d<float, metal::access::sample> texture0_ [[user(fake0)]]
, metal::sampler sampler0_ [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv, {}, varyings.color };
    metal::float4 _e4 = texture0_.sample(sampler0_, input.uv);
    float coverage = _e4.x;
    return main_Output { metal::float4(input.color.xyz, input.color.w * coverage) };
}
