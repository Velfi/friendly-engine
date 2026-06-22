// language: metal1.0
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct SkyUniforms {
    metal::float4 camera_right;
    metal::float4 camera_up;
    metal::float4 camera_forward;
    metal::float4 params0_;
    metal::float4 zenith_color;
    metal::float4 horizon_color;
    metal::float4 sun_direction;
    metal::float4 sun_color;
    metal::float4 sun_glow_color;
    metal::float4 sun_params;
    metal::float4 moon_direction;
    metal::float4 moon_color;
    metal::float4 moon_glow_color;
    metal::float4 moon_params;
    metal::float4 cloud_params0_;
    metal::float4 cloud_params1_;
    metal::float4 cloud_params2_;
};
struct FragmentInput {
    metal::float2 uv;
};

float hash11_(
    float value
) {
    float x = {};
    x = metal::sin(value * 12.9898) * 43758.547;
    float _e7 = x;
    return metal::fract(_e7);
}

float hash21_(
    metal::float2 p
) {
    float h = metal::dot(p, metal::float2(127.1, 311.7));
    return metal::fract(metal::sin(h) * 43758.547);
}

float valueNoise(
    metal::float2 p_1
) {
    metal::float2 cell = metal::floor(p_1);
    metal::float2 local_2 = metal::fract(p_1);
    metal::float2 curve = (local_2 * local_2) * (metal::float2(3.0, 3.0) - (2.0 * local_2));
    float _e11 = hash21_(cell);
    float _e16 = hash21_(cell + metal::float2(1.0, 0.0));
    float _e21 = hash21_(cell + metal::float2(0.0, 1.0));
    float _e26 = hash21_(cell + metal::float2(1.0, 1.0));
    return metal::mix(metal::mix(_e11, _e16, curve.x), metal::mix(_e21, _e26, curve.x), curve.y);
}

float fbm(
    metal::float2 p_2
) {
    float sum = 0.0;
    float amp = 0.54;
    float freq = 1.0;
    int i = 0;
    uint2 loop_bound = uint2(4294967295u);
    while(true) {
        if (metal::all(loop_bound == uint2(0u))) { break; }
        loop_bound -= uint2(loop_bound.y == 0u, 1u);
        int _e9 = i;
        if (_e9 >= 4) {
            break;
        }
        float _e12 = sum;
        float _e13 = freq;
        float _e15 = valueNoise(p_2 * _e13);
        float _e16 = amp;
        sum = _e12 + (_e15 * _e16);
        float _e19 = freq;
        freq = _e19 * 2.03;
        float _e22 = amp;
        amp = _e22 * 0.5;
        int _e25 = i;
        i = as_type<int>(as_type<uint>(_e25) + as_type<uint>(1));
    }
    float _e28 = sum;
    return _e28;
}

metal::float3 viewRayForUv(
    metal::float2 uv,
    constant SkyUniforms& sky
) {
    float tan_half = sky.params0_.x;
    float aspect = sky.params0_.y;
    float ndc_x = (((uv.x * 2.0) - 1.0) * tan_half) * aspect;
    float ndc_y = (1.0 - (uv.y * 2.0)) * tan_half;
    metal::float4 _e24 = sky.camera_forward;
    metal::float4 _e28 = sky.camera_right;
    metal::float4 _e34 = sky.camera_up;
    metal::float3 dir_4 = (_e24.xyz + (_e28.xyz * ndc_x)) + (_e34.xyz * ndc_y);
    return metal::normalize(dir_4);
}

metal::float3 starField(
    metal::float3 dir,
    float seed
) {
    float elevation = metal::asin(metal::clamp(dir.y, -1.0, 1.0));
    float azimuth = metal::atan2(dir.x, dir.z);
    float elev_deg = elevation * 57.29578;
    if (elev_deg < 8.0) {
        return metal::float3(0.0, 0.0, 0.0);
    }
    metal::float2 cell_1 = metal::floor(metal::float2(azimuth, elevation) / metal::float2(0.05));
    float _e27 = hash21_(cell_1 + metal::float2(seed, seed * 1.37));
    if (_e27 > 0.12) {
        return metal::float3(0.0, 0.0, 0.0);
    }
    metal::float2 local_3 = metal::fract(metal::float2(azimuth, elevation) / metal::float2(0.05));
    float _e44 = hash21_((cell_1 + metal::float2(1.0, 0.0)) + metal::float2(seed));
    float _e51 = hash21_((cell_1 + metal::float2(0.0, 1.0)) + metal::float2(seed));
    metal::float2 star_pos = metal::float2(_e44, _e51);
    float dist = metal::length(local_3 - star_pos);
    float _e61 = hash21_((cell_1 + metal::float2(2.7, 9.1)) + metal::float2(seed));
    float twinkle = 0.45 + (_e61 * 0.55);
    float _e72 = hash21_((cell_1 + metal::float2(5.3, 1.9)) + metal::float2(seed));
    float radius = (twinkle > 0.92) ? 0.12 : 0.06;
    float intensity = metal::smoothstep(radius, 0.0, dist) * twinkle;
    metal::float3 cool = metal::float3(0.7137255, 0.7764706, 1.0);
    metal::float3 warmc = metal::float3(1.0, 0.9254902, 0.76862746);
    metal::float3 color_2 = metal::mix(cool, warmc, _e72 * 0.38);
    return color_2 * intensity;
}

metal::float3 bodyContribution(
    metal::float3 dir_1,
    metal::float3 body_dir,
    float angular_radius_deg,
    float visibility,
    float enabled,
    metal::float3 color_1,
    metal::float3 glow_color,
    float cloud_cover
) {
    bool local = {};
    if (!((enabled < 0.5))) {
        local = visibility <= 0.01;
    } else {
        local = true;
    }
    bool _e16 = local;
    if (_e16) {
        return metal::float3(0.0, 0.0, 0.0);
    }
    float cos_angle = metal::clamp(metal::dot(dir_1, body_dir), -1.0, 1.0);
    float angle_deg = metal::acos(cos_angle) * 57.29578;
    float radius_deg = metal::max(angular_radius_deg, 0.05);
    float glow_radius_deg = radius_deg * 4.0;
    if (angle_deg > glow_radius_deg) {
        return metal::float3(0.0, 0.0, 0.0);
    }
    float glow_t = metal::clamp(1.0 - (angle_deg / glow_radius_deg), 0.0, 1.0);
    float disk_t = metal::clamp(1.0 - ((angle_deg - (radius_deg * 0.78)) / (radius_deg * 0.22)), 0.0, 1.0);
    float glow_occlusion = metal::mix(1.0, 0.48, metal::clamp(cloud_cover, 0.0, 1.0));
    float disk_occlusion = metal::mix(1.0, 0.18, metal::clamp(cloud_cover, 0.0, 1.0));
    metal::float3 glow = glow_color * ((((glow_t * glow_t) * visibility) * 0.32) * glow_occlusion);
    metal::float3 disk = color_1 * ((disk_t * visibility) * disk_occlusion);
    return glow + disk;
}

metal::float4 cloudSample(
    metal::float3 dir_2,
    metal::float2 uv_1,
    constant SkyUniforms& sky
) {
    float mask = {};
    metal::float3 cloud_color = {};
    float _e5 = sky.cloud_params0_.x;
    if (_e5 < 0.5) {
        return metal::float4(0.0, 0.0, 0.0, 0.0);
    }
    float _e16 = sky.cloud_params0_.y;
    float coverage = metal::clamp(_e16, 0.0, 1.0);
    float _e23 = sky.cloud_params0_.z;
    float softness = metal::clamp(_e23, 0.01, 1.0);
    float _e30 = sky.cloud_params0_.w;
    float scale = metal::clamp(_e30, 0.05, 8.0);
    float _e37 = sky.cloud_params1_.x;
    float height_bias = metal::clamp(_e37, 0.0, 1.0);
    metal::float4 _e43 = sky.cloud_params1_;
    metal::float2 drift_raw = _e43.yz;
    float drift_len = metal::max(metal::length(drift_raw), 0.001);
    metal::float2 drift_dir = drift_raw / metal::float2(drift_len);
    float seed_1 = sky.cloud_params2_.x;
    float time_s = sky.cloud_params2_.z;
    float elevation_1 = metal::clamp(dir_2.y, 0.0, 1.0);
    float horizon_fade = metal::smoothstep(0.02, 0.22, elevation_1);
    float zenith_fade = 1.0 - metal::smoothstep(0.78 + (height_bias * 0.16), 0.98, elevation_1);
    float band = horizon_fade * zenith_fade;
    if (band <= 0.001) {
        return metal::float4(0.0, 0.0, 0.0, 0.0);
    }
    float azimuth_1 = metal::atan2(dir_2.x, dir_2.z) * 0.15915494;
    metal::float2 sphere = metal::float2(azimuth_1, elevation_1 * 1.85);
    float _e101 = sky.cloud_params2_.y;
    metal::float2 parallax = (_e101 > 0.5) ? ((uv_1 - metal::float2(0.5, 0.5)) * 0.18) : metal::float2(0.0, 0.0);
    float _e107 = hash11_(seed_1 + 11.0);
    float _e110 = hash11_(seed_1 + 29.0);
    metal::float2 seed_offset = metal::float2(_e107, _e110) * 18.0;
    float _e117 = sky.cloud_params1_.w;
    metal::float2 drift = (drift_dir * _e117) * time_s;
    metal::float2 p_3 = (((sphere + parallax) * (1.45 / scale)) + seed_offset) + drift;
    float _e130 = fbm(p_3 * metal::float2(1.15, 0.62));
    float _e137 = fbm((p_3 * 2.35) + metal::float2(_e130 * 0.72));
    float _e146 = fbm((p_3 * metal::float2(4.4, 1.35)) + metal::float2(5.7, 1.9));
    float shaped = ((_e130 * 0.58) + (_e137 * 0.34)) + (_e146 * 0.08);
    float threshold = metal::mix(0.74, 0.34, coverage);
    mask = metal::smoothstep(threshold, threshold + (softness * 0.34), shaped) * band;
    float _e164 = mask;
    mask = _e164 * metal::smoothstep(0.0, 0.28, shaped);
    metal::float4 _e177 = sky.sun_direction;
    float sun_lift = metal::max(metal::dot(metal::normalize(dir_2 + metal::float3(0.0, 0.18, 0.0)), metal::normalize(_e177.xyz)), 0.0);
    float _e186 = sky.sun_params.y;
    float _e190 = sky.sun_params.z;
    float daylight = metal::clamp(_e186 * _e190, 0.0, 1.0);
    float rim = metal::pow(sun_lift, 4.0) * daylight;
    float underside = metal::clamp((0.55 - elevation_1) * 1.6, 0.0, 1.0);
    float light = metal::floor(metal::clamp((shaped * 4.0) + (rim * 1.6), 0.0, 3.99)) / 3.0;
    metal::float3 body = metal::float3(0.96862745, 0.9843137, 0.9490196);
    metal::float3 warm = metal::mix(metal::float3(255.0, 241.0, 207.0), metal::float3(255.0, 199.0, 143.0), metal::clamp(rim * 1.3, 0.0, 1.0)) / metal::float3(255.0);
    metal::float3 shadow = metal::mix(metal::float3(184.0, 201.0, 232.0), metal::float3(180.0, 168.0, 220.0), metal::clamp((rim * 0.6) + (underside * 0.35), 0.0, 1.0)) / metal::float3(255.0);
    cloud_color = metal::mix(shadow, body, light);
    metal::float3 _e259 = cloud_color;
    cloud_color = metal::mix(_e259, warm, rim * 0.58);
    metal::float3 _e263 = cloud_color;
    metal::float4 _e266 = sky.horizon_color;
    cloud_color = metal::mix(_e263, _e266.xyz, underside * 0.18);
    metal::float3 _e271 = cloud_color;
    cloud_color = _e271 * metal::mix(0.24, 1.0, daylight);
    metal::float3 _e276 = cloud_color;
    float _e277 = mask;
    return metal::float4(_e276, metal::clamp(_e277 * 0.88, 0.0, 0.88));
}

metal::float3 sunShaftContribution(
    metal::float3 dir_3,
    float cloud_alpha,
    constant SkyUniforms& sky
) {
    bool local_1 = {};
    float _e5 = sky.sun_params.z;
    if (!((_e5 < 0.5))) {
        float _e14 = sky.sun_params.y;
        local_1 = _e14 <= 0.01;
    } else {
        local_1 = true;
    }
    bool _e18 = local_1;
    if (_e18) {
        return metal::float3(0.0, 0.0, 0.0);
    }
    metal::float4 _e25 = sky.sun_direction;
    float sun_alignment = metal::max(metal::dot(dir_3, metal::normalize(_e25.xyz)), 0.0);
    float _e36 = sky.sun_params.y;
    float cone = metal::pow(sun_alignment, 18.0) * _e36;
    float break_light = metal::smoothstep(0.08, 0.52, cloud_alpha) * (1.0 - metal::smoothstep(0.62, 0.92, cloud_alpha));
    float _e59 = sky.cloud_params2_.x;
    float _e63 = sky.cloud_params2_.x;
    float _e66 = fbm(metal::float2(metal::atan2(dir_3.x, dir_3.z) * 12.0, dir_3.y * 4.0) + metal::float2(_e59, _e63));
    float streak_noise = 0.55 + (0.45 * _e66);
    float strength = ((cone * break_light) * streak_noise) * 0.24;
    metal::float4 _e77 = sky.sun_glow_color;
    return _e77.xyz * strength;
}

struct main_Input {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct main_Output {
    metal::float4 member [[color(0)]];
};
fragment main_Output main_(
  main_Input varyings [[stage_in]]
, constant SkyUniforms& sky [[user(fake0)]]
) {
    const FragmentInput input = { varyings.uv };
    metal::float3 color = {};
    metal::float3 _e2 = viewRayForUv(input.uv, sky);
    float t = metal::clamp(input.uv.y, 0.0, 1.0);
    float horizon_mix = metal::clamp(metal::pow(t, 1.8), 0.0, 1.0);
    metal::float4 _e15 = sky.zenith_color;
    metal::float4 _e19 = sky.horizon_color;
    color = metal::mix(_e15.xyz, _e19.xyz, horizon_mix);
    float star_visibility = sky.params0_.w;
    if (star_visibility > 0.001) {
        metal::float3 _e29 = color;
        float _e33 = sky.params0_.z;
        metal::float3 _e34 = starField(_e2, _e33);
        color = _e29 + (_e34 * star_visibility);
    }
    metal::float4 _e38 = cloudSample(_e2, input.uv, sky);
    metal::float3 _e39 = color;
    color = metal::mix(_e39, _e38.xyz, _e38.w);
    metal::float3 _e43 = color;
    metal::float3 _e45 = sunShaftContribution(_e2, _e38.w, sky);
    color = _e43 + _e45;
    metal::float3 _e47 = color;
    metal::float4 _e50 = sky.sun_direction;
    float _e55 = sky.sun_params.x;
    float _e59 = sky.sun_params.y;
    float _e63 = sky.sun_params.z;
    metal::float4 _e66 = sky.sun_color;
    metal::float4 _e70 = sky.sun_glow_color;
    metal::float3 _e73 = bodyContribution(_e2, _e50.xyz, _e55, _e59, _e63, _e66.xyz, _e70.xyz, _e38.w);
    color = _e47 + _e73;
    metal::float3 _e75 = color;
    metal::float4 _e78 = sky.moon_direction;
    float _e83 = sky.moon_params.x;
    float _e87 = sky.moon_params.y;
    float _e91 = sky.moon_params.z;
    metal::float4 _e94 = sky.moon_color;
    metal::float4 _e98 = sky.moon_glow_color;
    metal::float3 _e101 = bodyContribution(_e2, _e78.xyz, _e83, _e87, _e91, _e94.xyz, _e98.xyz, _e38.w);
    color = _e75 + _e101;
    metal::float3 _e103 = color;
    return main_Output { metal::float4(metal::max(_e103, metal::float3(0.0)), 1.0) };
}
