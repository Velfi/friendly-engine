// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct VertexUniforms {
    metal::float4x4 mvp;
    metal::float4x4 model;
};
struct VertexInput {
    metal::float4 position;
    metal::float3 normal;
    metal::float2 uv;
    char _pad3[8];
};
struct VertexOutput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
    metal::float3 world_pos;
    metal::float3 world_normal;
};

struct main_Input {
    metal::float4 position [[attribute(0)]];
    metal::float3 normal [[attribute(1)]];
    metal::float2 uv [[attribute(2)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
    metal::float3 world_pos [[user(loc1), center_perspective]];
    metal::float3 world_normal [[user(loc2), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant VertexUniforms& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.normal, varyings.uv };
    VertexOutput output = {};
    output.uv = input.uv;
    metal::float4x4 _e6 = uniforms.model;
    metal::float4 world_pos = _e6 * input.position;
    output.world_pos = world_pos.xyz;
    metal::float4 _e14 = uniforms.model[0];
    metal::float4 _e19 = uniforms.model[1];
    metal::float4 _e24 = uniforms.model[2];
    metal::float3x3 normal_matrix = metal::float3x3(_e14.xyz, _e19.xyz, _e24.xyz);
    output.world_normal = metal::normalize(normal_matrix * input.normal);
    metal::float4x4 _e34 = uniforms.mvp;
    output.position = _e34 * input.position;
    float _e41 = output.position.z;
    float _e44 = output.position.w;
    output.position.z = (_e41 + _e44) * 0.5;
    VertexOutput _e48 = output;
    const auto _tmp = _e48;
    return main_Output { _tmp.position, _tmp.uv, _tmp.world_pos, _tmp.world_normal };
}
