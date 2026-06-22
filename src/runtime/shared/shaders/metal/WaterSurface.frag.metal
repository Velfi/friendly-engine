// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
};

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, metal::float4 position [[position]]
, metal::texture2d<float, metal::access::sample> water_texture [[user(fake0)]]
, metal::sampler water_sampler [[user(fake0)]]
) {
    const FragmentInput input = { position, varyings.uv };
    metal::float4 _e4 = water_texture.sample(water_sampler, input.uv);
    return main_Output { _e4 };
}
