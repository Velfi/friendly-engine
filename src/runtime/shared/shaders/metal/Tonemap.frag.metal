// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct ToneMapUniforms {
    float exposure;
    float min_exposure;
    float max_exposure;
    uint enabled;
};
struct FragmentInput {
    metal::float2 uv;
};

metal::float3 acesFitted(
    metal::float3 color
) {
    return metal::clamp((color * ((2.51 * color) + metal::float3(0.03))) / ((color * ((2.43 * color) + metal::float3(0.59))) + metal::float3(0.14)), metal::float3(0.0), metal::float3(1.0));
}

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, metal::texture2d<float, metal::access::sample> hdr_color [[user(fake0)]]
, metal::sampler hdr_sampler [[user(fake0)]]
, constant ToneMapUniforms& tone [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv };
    metal::float4 _e4 = hdr_color.sample(hdr_sampler, input.uv);
    metal::float3 hdr = metal::max(_e4.xyz, metal::float3(0.0));
    float _e11 = tone.exposure;
    float _e14 = tone.min_exposure;
    float _e17 = tone.max_exposure;
    uint _e21 = tone.enabled;
    float exposure = (_e21 != 0u) ? metal::clamp(_e11, _e14, _e17) : 1.0;
    metal::float3 _e27 = acesFitted(hdr * exposure);
    return main_Output { metal::float4(_e27, 1.0) };
}
