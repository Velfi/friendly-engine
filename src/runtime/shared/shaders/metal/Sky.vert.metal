// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct VertexOutput {
    metal::float4 position;
    metal::float2 uv;
    char _pad2[8];
};

struct main_Input {
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
};
vertex main_Output main_(
  uint vertex_index [[vertex_id]]
) {
    VertexOutput output = {};
    metal::float2 tc = metal::float2(static_cast<float>((vertex_index << 1u) & 2u), static_cast<float>(vertex_index & 2u));
    output.position = metal::float4((tc * 2.0) - metal::float2(1.0), 0.0, 1.0);
    output.uv = metal::float2(tc.x, 1.0 - tc.y);
    VertexOutput _e26 = output;
    const auto _tmp = _e26;
    return main_Output { _tmp.position, _tmp.uv };
}
