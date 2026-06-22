// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct VertexUniforms {
    metal::float4x4 light_mvp;
};
struct VertexInput {
    metal::float4 position;
    metal::float3 normal;
    metal::float2 uv;
    char _pad3[8];
};
struct VertexOutput {
    metal::float4 position;
};

struct main_Input {
    metal::float4 position [[attribute(0)]];
    metal::float3 normal [[attribute(1)]];
    metal::float2 uv [[attribute(2)]];
};
struct main_Output {
    metal::float4 position [[position]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant VertexUniforms& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.normal, varyings.uv };
    VertexOutput output = {};
    metal::float4x4 _e5 = uniforms.light_mvp;
    output.position = _e5 * input.position;
    float _e12 = output.position.z;
    float _e15 = output.position.w;
    output.position.z = (_e12 + _e15) * 0.5;
    VertexOutput _e19 = output;
    const auto _tmp = _e19;
    return main_Output { _tmp.position };
}
