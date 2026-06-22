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

metal::float3 safeNormalize3_(
    metal::float3 value,
    metal::float3 fallback
) {
    float len_sq = metal::dot(value, value);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return value * metal::rsqrt(len_sq);
}

metal::float2 safeNormalize2_(
    metal::float2 value_1,
    metal::float2 fallback_1
) {
    float len_sq_1 = metal::dot(value_1, value_1);
    if (len_sq_1 <= 0.000001) {
        return fallback_1;
    }
    return value_1 * metal::rsqrt(len_sq_1);
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
    metal::float3 _e14 = safeNormalize3_(input.normal_height.xyz, metal::float3(0.0, 1.0, 0.0));
    float height = input.normal_height.w;
    float width = input.blade.x;
    float yaw = input.blade.y;
    float phase = input.blade.z;
    float variant = input.blade.w;
    metal::float3 _e33 = safeNormalize3_(metal::float3(metal::cos(yaw), 0.0, metal::sin(yaw)), metal::float3(1.0, 0.0, 0.0));
    metal::float3 _e43 = safeNormalize3_(metal::float3(-(metal::sin(yaw)), 0.0, metal::cos(yaw)), metal::float3(0.0, 0.0, 1.0));
    metal::float4 _e46 = uniforms.wind;
    metal::float2 _e55 = safeNormalize2_(_e46.xy + metal::float2(0.0001, 0.0), metal::float2(1.0, 0.0));
    float wind_speed = uniforms.wind.z;
    float time = uniforms.wind.w;
    float wind_strength = uniforms.controls.x;
    float bend_strength = uniforms.controls.y;
    float stiffness = uniforms.controls.z;
    float fade = uniforms.controls.w;
    uint _e87 = uniforms.counts.x;
    uint count = metal::min(_e87, 16u);
    uint2 loop_bound = uint2(4294967295u);
    bool loop_init = true;
    while(true) {
        if (metal::all(loop_bound == uint2(0u))) { break; }
        loop_bound -= uint2(loop_bound.y == 0u, 1u);
        if (!loop_init) {
            uint _e142 = i;
            i = _e142 + 1u;
        }
        loop_init = false;
        uint _e92 = i;
        if (_e92 < 16u) {
        } else {
            break;
        }
        {
            uint _e95 = i;
            if (_e95 >= count) {
                break;
            }
            uint _e99 = i;
            GrassInfluencer influencer = uniforms.influencers.inner[_e99];
            metal::float2 to_blade = root.xz - influencer.position_radius.xz;
            float dist = metal::length(to_blade);
            float radius = metal::max(influencer.position_radius.w, 0.001);
            float falloff = metal::max(0.0, 1.0 - (dist / radius));
            metal::float2 radial = (dist > 0.001) ? (to_blade / metal::float2(metal::max(dist, 0.001))) : metal::float2(0.0, 1.0);
            metal::float2 _e126 = push;
            push = _e126 + ((radial * falloff) * influencer.velocity_strength.w);
            metal::float2 _e132 = push;
            push = _e132 + (((influencer.velocity_strength.xz * falloff) * 0.35) * influencer.velocity_strength.w);
        }
    }
    float gust = metal::sin(((metal::dot(root.xz, _e55 * 0.085) + (time * wind_speed)) + phase) + (variant * 0.73));
    float flutter = metal::sin((metal::dot(root.xz, metal::float2(0.19, -0.13)) + (time * ((wind_speed * 2.7) + 0.4))) + (phase * 1.7)) * 0.22;
    metal::float2 wind_push = (_e55 * (gust + flutter)) * wind_strength;
    float recover = 1.0 - (stiffness * 0.58);
    float tip_weight = _e5 * _e5;
    metal::float2 _e183 = push;
    metal::float2 bend = ((((wind_push * 0.42) + ((_e183 * bend_strength) * 0.72)) * recover) * height) * tip_weight;
    float taper = width * metal::mix(1.0, 0.18, _e5);
    float curl = (metal::sin(_e5 * 3.1415927) * width) * (0.2 + (0.04 * variant));
    world = root + ((_e14 * height) * _e5);
    metal::float3 _e208 = world;
    world = _e208 + ((_e33 * _e4) * taper);
    metal::float3 _e212 = world;
    world = _e212 + (_e43 * curl);
    metal::float3 _e215 = world;
    world = _e215 + metal::float3(bend.x, 0.0, bend.y);
    metal::float3 _e233 = safeNormalize3_(((_e14 * 0.48) + ((_e33 * _e4) * 0.42)) - (_e43 * (0.18 + (0.22 * _e5))), _e14);
    curved_normal = _e233;
    metal::float3 _e235 = curved_normal;
    metal::float3 _e243 = safeNormalize3_(_e235 + (metal::float3(bend.x, 0.0, bend.y) * 0.18), _e14);
    curved_normal = _e243;
    output.color = input.color;
    metal::float3 _e248 = curved_normal;
    output.world_normal = _e248;
    output.blade_uv = metal::float2((_e4 * 0.5) + 0.5, _e5);
    metal::float4x4 _e258 = uniforms.view_proj;
    metal::float3 _e259 = world;
    output.position = _e258 * metal::float4(_e259, 1.0);
    float _e267 = output.position.z;
    float _e270 = output.position.w;
    output.position.z = (_e267 + _e270) * 0.5;
    output.color.w = input.color.w * fade;
    VertexOutput _e279 = output;
    const auto _tmp = _e279;
    return main_Output { _tmp.position, _tmp.color, _tmp.world_normal, _tmp.blade_uv };
}
