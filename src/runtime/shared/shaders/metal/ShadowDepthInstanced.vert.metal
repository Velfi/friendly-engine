// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct SceneUniforms {
    metal::float4x4 light_view_proj;
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
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant SceneUniforms& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.normal, varyings.uv, {}, varyings.instance_m0_, varyings.instance_m1_, varyings.instance_m2_, varyings.instance_m3_ };
    VertexOutput output = {};
    metal::float4x4 _e2 = instanceModel(input);
    metal::float4x4 _e6 = uniforms.light_view_proj;
    output.position = (_e6 * _e2) * input.position;
    float _e14 = output.position.z;
    float _e17 = output.position.w;
    output.position.z = (_e14 + _e17) * 0.5;
    VertexOutput _e21 = output;
    const auto _tmp = _e21;
    return main_Output { _tmp.position };
}
