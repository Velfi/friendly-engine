// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct GrassInfluencer {
    metal::float4 position_radius;
    metal::float4 velocity_strength;
};
struct type_3 {
    GrassInfluencer inner[16];
};
struct GrassUniforms {
    metal::float4x4 view_proj;
    metal::float4 wind;
    metal::float4 controls;
    type_3 influencers;
    metal::uint4 counts;
};
struct VertexInput {
    metal::float4 position;
    metal::float4 normal_height;
    metal::float4 color;
    metal::float4 blade;
    uint vertex_index;
    char _pad5[12];
};
struct VertexOutput {
    metal::float4 position;
    metal::float4 color;
    metal::float3 world_normal;
    metal::float2 blade_uv;
    char _pad4[8];
};

float sideForVertex(
    uint idx
) {
    bool local = {};
    bool local_1 = {};
    if (!((idx == 0u))) {
        local = idx == 3u;
    } else {
        local = true;
    }
    bool _e9 = local;
    if (!(_e9)) {
        local_1 = idx == 5u;
    } else {
        local_1 = true;
    }
    bool _e16 = local_1;
    if (_e16) {
        return -1.0;
    }
    return 1.0;
}

float heightForVertex(
    uint idx_1
) {
    bool local_2 = {};
    bool local_3 = {};
    if (!((idx_1 == 0u))) {
        local_2 = idx_1 == 1u;
    } else {
        local_2 = true;
    }
    bool _e9 = local_2;
    if (!(_e9)) {
        local_3 = idx_1 == 3u;
    } else {
        local_3 = true;
    }
    bool _e16 = local_3;
    if (_e16) {
        return 0.0;
    }
    return 1.0;
}
uint naga_mod(uint lhs, uint rhs) {
    return lhs % metal::select(rhs, 1u, rhs == 0u);
}


struct main_Input {
    metal::float4 position [[attribute(0)]];
    metal::float4 normal_height [[attribute(1)]];
    metal::float4 color [[attribute(2)]];
    metal::float4 blade [[attribute(3)]];
};
struct main_Output {
    metal::float4 position [[position]];
    metal::float4 color [[user(loc0), center_perspective]];
    metal::float3 world_normal [[user(loc1), center_perspective]];
    metal::float2 blade_uv [[user(loc2), center_perspective]];
};
vertex main_Output main_(
  main_Input varyings [[stage_in]]
, uint vertex_index [[vertex_id]]
, constant GrassUniforms& uniforms [[user(fake0)]]
) {
    const VertexInput input = { varyings.position, varyings.normal_height, varyings.color, varyings.blade, vertex_index };
    metal::float2 push = metal::float2(0.0, 0.0);
    uint i = 0u;
    metal::float3 world = {};
    metal::float3 curved_normal = {};
    VertexOutput output = {};
    uint local_idx = naga_mod(input.vertex_index, 6u);
    float _e4 = sideForVertex(local_idx);
    float _e5 = heightForVertex(local_idx);
    metal::float3 root = input.position.xyz;
    metal::float3 terrain_normal = metal::normalize(input.normal_height.xyz);
    float height = input.normal_height.w;
    float width = input.blade.x;
    float yaw = input.blade.y;
    float phase = input.blade.z;
    float variant = input.blade.w;
    metal::float3 right = metal::normalize(metal::float3(metal::cos(yaw), 0.0, metal::sin(yaw)));
    metal::float3 forward = metal::normalize(metal::float3(-(metal::sin(yaw)), 0.0, metal::cos(yaw)));
    metal::float4 _e34 = uniforms.wind;
    metal::float2 wind_dir = metal::normalize(_e34.xy + metal::float2(0.0001, 0.0));
    float wind_speed = uniforms.wind.z;
    float time = uniforms.wind.w;
    float wind_strength = uniforms.controls.x;
    float bend_strength = uniforms.controls.y;
    float stiffness = uniforms.controls.z;
    float fade = uniforms.controls.w;
    uint _e72 = uniforms.counts.x;
    uint count = metal::min(_e72, 16u);
    uint2 loop_bound = uint2(4294967295u);
    bool loop_init = true;
    while(true) {
        if (metal::all(loop_bound == uint2(0u))) { break; }
        loop_bound -= uint2(loop_bound.y == 0u, 1u);
        if (!loop_init) {
            uint _e127 = i;
            i = _e127 + 1u;
        }
        loop_init = false;
        uint _e77 = i;
        if (_e77 < 16u) {
        } else {
            break;
        }
        {
            uint _e80 = i;
            if (_e80 >= count) {
                break;
            }
            uint _e84 = i;
            GrassInfluencer influencer = uniforms.influencers.inner[_e84];
            metal::float2 to_blade = root.xz - influencer.position_radius.xz;
            float dist = metal::length(to_blade);
            float radius = metal::max(influencer.position_radius.w, 0.001);
            float falloff = metal::max(0.0, 1.0 - (dist / radius));
            metal::float2 radial = (dist > 0.001) ? (to_blade / metal::float2(metal::max(dist, 0.001))) : metal::float2(0.0, 1.0);
            metal::float2 _e111 = push;
            push = _e111 + ((radial * falloff) * influencer.velocity_strength.w);
            metal::float2 _e117 = push;
            push = _e117 + (((influencer.velocity_strength.xz * falloff) * 0.35) * influencer.velocity_strength.w);
        }
    }
    float gust = metal::sin(((metal::dot(root.xz, wind_dir * 0.085) + (time * wind_speed)) + phase) + (variant * 0.73));
    float flutter = metal::sin((metal::dot(root.xz, metal::float2(0.19, -0.13)) + (time * ((wind_speed * 2.7) + 0.4))) + (phase * 1.7)) * 0.22;
    metal::float2 wind_push = (wind_dir * (gust + flutter)) * wind_strength;
    float recover = 1.0 - (stiffness * 0.58);
    float tip_weight = _e5 * _e5;
    metal::float2 _e168 = push;
    metal::float2 bend = ((((wind_push * 0.42) + ((_e168 * bend_strength) * 0.72)) * recover) * height) * tip_weight;
    float taper = width * metal::mix(1.0, 0.18, _e5);
    float curl = (metal::sin(_e5 * 3.1415927) * width) * (0.2 + (0.04 * variant));
    world = root + ((terrain_normal * height) * _e5);
    metal::float3 _e193 = world;
    world = _e193 + ((right * _e4) * taper);
    metal::float3 _e197 = world;
    world = _e197 + (forward * curl);
    metal::float3 _e200 = world;
    world = _e200 + metal::float3(bend.x, 0.0, bend.y);
    curved_normal = metal::normalize(((terrain_normal * 0.48) + ((right * _e4) * 0.42)) - (forward * (0.18 + (0.22 * _e5))));
    metal::float3 _e220 = curved_normal;
    curved_normal = metal::normalize(_e220 + (metal::float3(bend.x, 0.0, bend.y) * 0.18));
    output.color = input.color;
    metal::float3 _e233 = curved_normal;
    output.world_normal = _e233;
    output.blade_uv = metal::float2((_e4 * 0.5) + 0.5, _e5);
    metal::float4x4 _e243 = uniforms.view_proj;
    metal::float3 _e244 = world;
    output.position = _e243 * metal::float4(_e244, 1.0);
    float _e252 = output.position.z;
    float _e255 = output.position.w;
    output.position.z = (_e252 + _e255) * 0.5;
    output.color.w = input.color.w * fade;
    VertexOutput _e264 = output;
    const auto _tmp = _e264;
    return main_Output { _tmp.position, _tmp.color, _tmp.world_normal, _tmp.blade_uv };
}
