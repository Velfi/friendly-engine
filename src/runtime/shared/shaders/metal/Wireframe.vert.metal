// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct UniformBlock {
    metal::float4x4 transform;
};
struct VertexInput {
    metal::float4 position;
};
struct VertexOutput {
    metal::float4 position;
    metal::float4 color;
};

struct main_Input {
    metal::float4 position [[attribute(0)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float4 color [[user(loc0), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, constant UniformBlock& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position };
    VertexOutput output = {};
    output.color = metal::float4(0.78431374, 0.8235294, 0.9019608, 1.0);
    metal::float4x4 _e11 = uniforms.transform;
    output.position = _e11 * input.position;
    float _e18 = output.position.z;
    float _e21 = output.position.w;
    output.position.z = (_e18 + _e21) * 0.5;
    VertexOutput _e25 = output;
    const auto _tmp = _e25;
    return main_Output { _tmp.position, _tmp.color };
}
