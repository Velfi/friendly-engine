// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct UniformBlock {
    metal::float4x4 transform;
};
struct VertexInput {
    metal::float3 position;
    metal::float4 color;
};
struct VertexOutput {
    metal::float4 position;
    metal::float4 color;
};

struct main_Input {
    metal::float3 position [[attribute(0)]];
    metal::float4 color [[attribute(1)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float4 color [[user(loc0), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant UniformBlock& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.color };
    VertexOutput output = {};
    output.color = input.color;
    metal::float4x4 _e7 = uniforms.transform;
    output.position = _e7 * metal::float4(input.position, 1.0);
    float _e16 = output.position.z;
    float _e19 = output.position.w;
    output.position.z = (_e16 + _e19) * 0.5;
    VertexOutput _e23 = output;
    const auto _tmp = _e23;
    return main_Output { _tmp.position, _tmp.color };
}
