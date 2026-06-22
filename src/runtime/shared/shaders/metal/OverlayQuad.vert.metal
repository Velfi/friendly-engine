// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct UniformBlock {
    metal::float4x4 matrix_transform;
};
struct VertexInput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
    metal::float4 color;
};
struct VertexOutput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
    metal::float4 color;
};

struct main_Input {
    metal::float4 position [[attribute(0)]];
    metal::float2 uv [[attribute(1)]];
    metal::float4 color [[attribute(2)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
    metal::float4 color [[user(loc1), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant UniformBlock& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.uv, {}, varyings.color };
    VertexOutput output = {};
    output.uv = input.uv;
    output.color = input.color;
    metal::float4x4 _e9 = uniforms.matrix_transform;
    output.position = _e9 * input.position;
    VertexOutput _e12 = output;
    const auto _tmp = _e12;
    return main_Output { _tmp.position, _tmp.uv, _tmp.color };
}
