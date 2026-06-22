// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct SceneUniforms {
    metal::float4x4 view_proj;
};
struct VertexInput {
    metal::float4 position;
    metal::float3 normal;
    metal::float2 uv;
    char _pad3[8];
    metal::float4 instance_m0_;
    metal::float4 instance_m1_;
    metal::float4 instance_m2_;
    metal::float4 instance_m3_;
};
struct VertexOutput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
    metal::float3 world_pos;
    metal::float3 world_normal;
};

metal::float4x4 instanceModel(
    VertexInput input_1
) {
    return metal::float4x4(input_1.instance_m0_, input_1.instance_m1_, input_1.instance_m2_, input_1.instance_m3_);
}

struct main_Input {
    metal::float4 position [[attribute(0)]];
    metal::float3 normal [[attribute(1)]];
    metal::float2 uv [[attribute(2)]];
    metal::float4 instance_m0_ [[attribute(3)]];
    metal::float4 instance_m1_ [[attribute(4)]];
    metal::float4 instance_m2_ [[attribute(5)]];
    metal::float4 instance_m3_ [[attribute(6)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
    metal::float3 world_pos [[user(loc1), center_perspective]];
    metal::float3 world_normal [[user(loc2), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant SceneUniforms& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.normal, varyings.uv, {}, varyings.instance_m0_, varyings.instance_m1_, varyings.instance_m2_, varyings.instance_m3_ };
    VertexOutput output = {};
    output.uv = input.uv;
    metal::float4x4 _e4 = instanceModel(input);
    metal::float4 world_pos = _e4 * input.position;
    output.world_pos = world_pos.xyz;
    metal::float3x3 normal_matrix = metal::float3x3(_e4[0].xyz, _e4[1].xyz, _e4[2].xyz);
    output.world_normal = metal::normalize(normal_matrix * input.normal);
    metal::float4x4 _e23 = uniforms.view_proj;
    output.position = _e23 * world_pos;
    float _e29 = output.position.z;
    float _e32 = output.position.w;
    output.position.z = (_e29 + _e32) * 0.5;
    VertexOutput _e36 = output;
    const auto _tmp = _e36;
    return main_Output { _tmp.position, _tmp.uv, _tmp.world_pos, _tmp.world_normal };
}
