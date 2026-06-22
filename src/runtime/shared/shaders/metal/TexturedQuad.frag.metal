// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float2 uv;
};

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, metal::texture2d<float, metal::access::sample> texture0_ [[user(fake0)]]
, metal::sampler sampler0_ [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv };
    metal::float4 _e4 = texture0_.sample(sampler0_, input.uv);
    return main_Output { _e4 };
}
