const MAX_POINT_LIGHTS: u32 = 4u;

@group(0) @binding(0)
var texture0: texture_2d<f32>;

@group(0) @binding(1)
var sampler0: sampler;

@group(0) @binding(2)
var shadow_map: texture_depth_2d;

@group(0) @binding(3)
var shadow_sampler: sampler_comparison;

struct LightingUniforms {
    ambient: vec4<f32>,
    sun_direction: vec4<f32>,
    sun_color: vec4<f32>,
    point_light_count: u32,
    receive_shadows: u32,
    shadows_enabled: u32,
    fog_enabled: u32,
    point_positions: array<vec4<f32>, MAX_POINT_LIGHTS>,
    point_colors: array<vec4<f32>, MAX_POINT_LIGHTS>,
    light_view_proj: mat4x4<f32>,
    fog_color: vec4<f32>,
    fog_distances: vec4<f32>,
    camera_position: vec4<f32>,
    material: vec4<f32>,
};

@group(1) @binding(0)
var<uniform> lighting: LightingUniforms;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
    @location(1) world_pos: vec3<f32>,
    @location(2) world_normal: vec3<f32>,
};

fn shadowFactor(world_pos: vec3<f32>) -> f32 {
    if (lighting.shadows_enabled == 0u || lighting.receive_shadows == 0u) {
        return 1.0;
    }
    let shadow_pos = lighting.light_view_proj * vec4<f32>(world_pos, 1.0);
    let ndc = shadow_pos.xyz / shadow_pos.w;
    let uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return 1.0;
    }
    let depth = textureSampleCompareLevel(shadow_map, shadow_sampler, uv, ndc.z - 0.002);
    return depth;
}

fn heightFogScale(world_y: f32, height_falloff_k: f32) -> f32 {
    if (world_y <= 0.0) {
        return 1.0;
    }
    return exp(-world_y * height_falloff_k);
}

fn fogFactor(world_pos: vec3<f32>) -> f32 {
    if (lighting.fog_enabled == 0u) {
        return 0.0;
    }
    let start_m = lighting.fog_distances.x;
    let end_m = lighting.fog_distances.y;
    let density = lighting.fog_distances.z;
    let height_k = lighting.fog_distances.w;
    let view = world_pos - lighting.camera_position.xyz;
    let distance_m = length(view);
    if (distance_m <= start_m) {
        return 0.0;
    }
    let dir = view / distance_m;
    let seg_len = (distance_m - start_m) / 4.0;
    var optical_depth = 0.0;
    var i = 0u;
    loop {
        if (i >= 4u) {
            break;
        }
        let t = start_m + seg_len * (f32(i) + 0.5);
        let sample_pos = lighting.camera_position.xyz + dir * t;
        optical_depth += density * heightFogScale(sample_pos.y, height_k) * seg_len;
        i += 1u;
    }
    return clamp(1.0 - exp(-optical_depth), 0.0, 1.0);
}

fn dissolveNoise(world_pos: vec3<f32>) -> f32 {
    let cell = floor(world_pos * 14.0);
    let seed = dot(cell, vec3<f32>(12.9898, 78.233, 37.719));
    return fract(sin(seed) * 43758.5453);
}

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let base = textureSample(texture0, sampler0, input.uv);
    let dissolve_amount = clamp(lighting.material.x, 0.0, 1.0);
    let dissolve_inverted = lighting.material.y > 0.5;
    let dissolve_sample = dissolveNoise(input.world_pos);
    if (!dissolve_inverted && dissolve_amount > 0.001 && dissolve_sample < dissolve_amount) {
        discard;
    }
    if (dissolve_inverted && dissolve_sample >= dissolve_amount) {
        discard;
    }
    let n = normalize(input.world_normal);
    var color = base.rgb * lighting.ambient.rgb;

    let sun_dir = normalize(lighting.sun_direction.xyz);
    let sun_ndotl = max(dot(n, -sun_dir), 0.0);
    color += base.rgb * lighting.sun_color.rgb * sun_ndotl * lighting.sun_direction.w * shadowFactor(input.world_pos);

    var i: u32 = 0u;
    loop {
        if (i >= lighting.point_light_count || i >= MAX_POINT_LIGHTS) {
            break;
        }
        let light_pos = lighting.point_positions[i].xyz;
        let to_light = light_pos - input.world_pos;
        let dist_sq = dot(to_light, to_light);
        if (dist_sq > 0.0001) {
            let atten = 1.0 / (1.0 + dist_sq * 0.02);
            let l = normalize(to_light);
            let ndotl = max(dot(n, l), 0.0);
            color += base.rgb * lighting.point_colors[i].rgb * ndotl * atten;
        }
        i += 1u;
    }

    let fog_t = fogFactor(input.world_pos);
    color = mix(color, lighting.fog_color.rgb, fog_t);

    return vec4<f32>(color, base.a);
}
