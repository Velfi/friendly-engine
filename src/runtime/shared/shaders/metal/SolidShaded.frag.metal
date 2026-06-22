// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct FragmentInput {
    metal::float2 uv;
    char _pad1[8];
    metal::float3 world_pos;
    metal::float3 world_normal;
};

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
    metal::float3 world_pos [[user(loc1), center_perspective]];
    metal::float3 world_normal [[user(loc2), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
) {
    const FragmentInput input = { varyings.uv, {}, varyings.world_pos, varyings.world_normal };
    metal::float3 normal = metal::normalize(input.world_normal);
    metal::float3 light_dir = metal::float3(0.3674047, 0.8922686, 0.26243195);
    float lit = metal::max(metal::dot(normal, light_dir), 0.0);
    metal::float3 clay = metal::float3(0.72, 0.68, 0.6);
    float rim = metal::pow(1.0 - metal::abs(normal.z), 2.0) * 0.08;
    float shade = (0.48 + (lit * 0.42)) + rim;
    return main_Output { metal::float4(clay * shade, 1.0) };
}
