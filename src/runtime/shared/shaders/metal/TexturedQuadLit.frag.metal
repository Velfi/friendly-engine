// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_7 {
    metal::float4 inner[4];
};
struct LightingUniforms {
    metal::float4 ambient;
    metal::float4 sun_direction;
    metal::float4 sun_color;
    uint point_light_count;
    uint receive_shadows;
    uint shadows_enabled;
    uint fog_enabled;
    type_7 point_positions;
    type_7 point_colors;
    metal::float4x4 light_view_proj;
    metal::float4 fog_color;
    metal::float4 fog_distances;
    metal::float4 camera_position;
    metal::float4 material;
};
struct FragmentInput {
    metal::float2 uv;
    char _pad1[8];
    metal::float3 world_pos;
    metal::float3 world_normal;
};
constant uint MAX_POINT_LIGHTS = 4u;

float shadowFactor(
    metal::float3 world_pos,
    metal::depth2d<float, metal::access::sample> shadow_map,
    metal::sampler shadow_sampler,
    constant LightingUniforms& lighting
) {
    bool local_4 = {};
    bool local_5 = {};
    bool local_6 = {};
    bool local_7 = {};
    uint _e3 = lighting.shadows_enabled;
    if (!((_e3 == 0u))) {
        uint _e11 = lighting.receive_shadows;
        local_4 = _e11 == 0u;
    } else {
        local_4 = true;
    }
    bool _e15 = local_4;
    if (_e15) {
        return 1.0;
    }
    metal::float4x4 _e19 = lighting.light_view_proj;
    metal::float4 shadow_pos = _e19 * metal::float4(world_pos, 1.0);
    metal::float3 ndc = shadow_pos.xyz / metal::float3(shadow_pos.w);
    metal::float2 uv = metal::float2((ndc.x * 0.5) + 0.5, 0.5 - (ndc.y * 0.5));
    if (!((uv.x < 0.0))) {
        local_5 = uv.x > 1.0;
    } else {
        local_5 = true;
    }
    bool _e48 = local_5;
    if (!(_e48)) {
        local_6 = uv.y < 0.0;
    } else {
        local_6 = true;
    }
    bool _e56 = local_6;
    if (!(_e56)) {
        local_7 = uv.y > 1.0;
    } else {
        local_7 = true;
    }
    bool _e64 = local_7;
    if (_e64) {
        return 1.0;
    }
    float depth = shadow_map.sample_compare(shadow_sampler, uv, ndc.z - 0.002);
    return depth;
}

float heightFogScale(
    float world_y,
    float height_falloff_k
) {
    if (world_y <= 0.0) {
        return 1.0;
    }
    return metal::exp(-(world_y) * height_falloff_k);
}

float fogFactor(
    metal::float3 world_pos_1,
    constant LightingUniforms& lighting
) {
    float optical_depth = 0.0;
    uint i_1 = 0u;
    uint _e3 = lighting.fog_enabled;
    if (_e3 == 0u) {
        return 0.0;
    }
    float start_m = lighting.fog_distances.x;
    float end_m = lighting.fog_distances.y;
    float density = lighting.fog_distances.z;
    float height_k = lighting.fog_distances.w;
    metal::float4 _e25 = lighting.camera_position;
    metal::float3 view = world_pos_1 - _e25.xyz;
    float distance_m = metal::length(view);
    if (distance_m <= start_m) {
        return 0.0;
    }
    metal::float3 dir = view / metal::float3(distance_m);
    float seg_len = (distance_m - start_m) / 4.0;
    uint2 loop_bound = uint2(4294967295u);
    while(true) {
        if (metal::all(loop_bound == uint2(0u))) { break; }
        loop_bound -= uint2(loop_bound.y == 0u, 1u);
        uint _e40 = i_1;
        if (_e40 >= 4u) {
            break;
        }
        uint _e43 = i_1;
        float t = start_m + (seg_len * (static_cast<float>(_e43) + 0.5));
        metal::float4 _e51 = lighting.camera_position;
        metal::float3 sample_pos = _e51.xyz + (dir * t);
        float _e55 = optical_depth;
        float _e57 = heightFogScale(sample_pos.y, height_k);
        optical_depth = _e55 + ((density * _e57) * seg_len);
        uint _e61 = i_1;
        i_1 = _e61 + 1u;
    }
    float _e64 = optical_depth;
    return metal::clamp(1.0 - metal::exp(-(_e64)), 0.0, 1.0);
}

float dissolveNoise(
    metal::float3 world_pos_2
) {
    metal::float3 cell = metal::floor(world_pos_2 * 14.0);
    float seed = metal::dot(cell, metal::float3(12.9898, 78.233, 37.719));
    return metal::fract(metal::sin(seed) * 43758.547);
}

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
, metal::texture2d<float, metal::access::sample> texture0_ [[user(fake0)]]
, metal::sampler sampler0_ [[user(fake0)]]
, metal::depth2d<float, metal::access::sample> shadow_map [[user(fake0)]]
, metal::sampler shadow_sampler [[user(fake0)]]
, constant LightingUniforms& lighting [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv, {}, varyings.world_pos, varyings.world_normal };
    bool local = {};
    bool local_1 = {};
    bool local_2 = {};
    metal::float3 color = {};
    uint i = 0u;
    bool local_3 = {};
    metal::float4 base = texture0_.sample(sampler0_, input.uv);
    float _e8 = lighting.material.x;
    float dissolve_amount = metal::clamp(_e8, 0.0, 1.0);
    float _e15 = lighting.material.y;
    bool dissolve_inverted = _e15 > 0.5;
    float _e19 = dissolveNoise(input.world_pos);
    if (!(dissolve_inverted)) {
        local = dissolve_amount > 0.001;
    } else {
        local = false;
    }
    bool _e26 = local;
    if (_e26) {
        local_1 = _e19 < dissolve_amount;
    } else {
        local_1 = false;
    }
    bool _e31 = local_1;
    if (_e31) {
        metal::discard_fragment();
    }
    if (dissolve_inverted) {
        local_2 = _e19 >= dissolve_amount;
    } else {
        local_2 = false;
    }
    bool _e36 = local_2;
    if (_e36) {
        metal::discard_fragment();
    }
    metal::float3 n = metal::normalize(input.world_normal);
    metal::float4 _e42 = lighting.ambient;
    color = base.xyz * _e42.xyz;
    metal::float4 _e48 = lighting.sun_direction;
    metal::float3 sun_dir = metal::normalize(_e48.xyz);
    float sun_ndotl = metal::max(metal::dot(n, -(sun_dir)), 0.0);
    metal::float3 _e55 = color;
    metal::float4 _e59 = lighting.sun_color;
    float _e66 = lighting.sun_direction.w;
    float _e69 = shadowFactor(input.world_pos, shadow_map, shadow_sampler, lighting);
    color = _e55 + ((((base.xyz * _e59.xyz) * sun_ndotl) * _e66) * _e69);
    uint2 loop_bound_1 = uint2(4294967295u);
    while(true) {
        if (metal::all(loop_bound_1 == uint2(0u))) { break; }
        loop_bound_1 -= uint2(loop_bound_1.y == 0u, 1u);
        uint _e74 = i;
        uint _e77 = lighting.point_light_count;
        if (!((_e74 >= _e77))) {
            uint _e82 = i;
            local_3 = _e82 >= MAX_POINT_LIGHTS;
        } else {
            local_3 = true;
        }
        bool _e86 = local_3;
        if (_e86) {
            break;
        }
        uint _e89 = i;
        metal::float4 _e91 = lighting.point_positions.inner[_e89];
        metal::float3 light_pos = _e91.xyz;
        metal::float3 to_light = light_pos - input.world_pos;
        float dist_sq = metal::dot(to_light, to_light);
        if (dist_sq > 0.0001) {
            float atten = 1.0 / (1.0 + (dist_sq * 0.02));
            metal::float3 l = metal::normalize(to_light);
            float ndotl = metal::max(metal::dot(n, l), 0.0);
            metal::float3 _e108 = color;
            uint _e112 = i;
            metal::float4 _e114 = lighting.point_colors.inner[_e112];
            color = _e108 + (((base.xyz * _e114.xyz) * ndotl) * atten);
        }
        uint _e120 = i;
        i = _e120 + 1u;
    }
    float _e124 = fogFactor(input.world_pos, lighting);
    metal::float3 _e125 = color;
    metal::float4 _e128 = lighting.fog_color;
    color = metal::mix(_e125, _e128.xyz, _e124);
    metal::float3 _e131 = color;
    return main_Output { metal::float4(_e131, base.w) };
}
