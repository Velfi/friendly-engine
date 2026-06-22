struct GrassInfluencer {
    position_radius: vec4<f32>,
    velocity_strength: vec4<f32>,
};

struct GrassUniforms {
    view_proj: mat4x4<f32>,
    wind: vec4<f32>,
    controls: vec4<f32>,
    influencers: array<GrassInfluencer, 16>,
    counts: vec4<u32>,
};

@group(0) @binding(0)
var<uniform> uniforms: GrassUniforms;

struct VertexInput {
    @location(0) position: vec4<f32>,
    @location(1) normal_height: vec4<f32>,
    @location(2) color: vec4<f32>,
    @location(3) blade: vec4<f32>,
    @builtin(vertex_index) vertex_index: u32,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) blade_uv: vec2<f32>,
};

fn sideForVertex(idx: u32) -> f32 {
    if (idx == 0u || idx == 3u || idx == 5u) {
        return -1.0;
    }
    return 1.0;
}

fn heightForVertex(idx: u32) -> f32 {
    if (idx == 0u || idx == 1u || idx == 3u) {
        return 0.0;
    }
    return 1.0;
}

fn safeNormalize3(value: vec3<f32>, fallback: vec3<f32>) -> vec3<f32> {
    let len_sq = dot(value, value);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return value * inverseSqrt(len_sq);
}

fn safeNormalize2(value: vec2<f32>, fallback: vec2<f32>) -> vec2<f32> {
    let len_sq = dot(value, value);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return value * inverseSqrt(len_sq);
}

@vertex
fn main(input: VertexInput) -> VertexOutput {
    let local_idx = input.vertex_index % 6u;
    let side = sideForVertex(local_idx);
    let t = heightForVertex(local_idx);
    let root = input.position.xyz;
    let terrain_normal = safeNormalize3(input.normal_height.xyz, vec3<f32>(0.0, 1.0, 0.0));
    let height = input.normal_height.w;
    let width = input.blade.x;
    let yaw = input.blade.y;
    let phase = input.blade.z;
    let variant = input.blade.w;

    let right = safeNormalize3(vec3<f32>(cos(yaw), 0.0, sin(yaw)), vec3<f32>(1.0, 0.0, 0.0));
    let forward = safeNormalize3(vec3<f32>(-sin(yaw), 0.0, cos(yaw)), vec3<f32>(0.0, 0.0, 1.0));
    let wind_dir = safeNormalize2(uniforms.wind.xy + vec2<f32>(0.0001, 0.0), vec2<f32>(1.0, 0.0));
    let wind_speed = uniforms.wind.z;
    let time = uniforms.wind.w;
    let wind_strength = uniforms.controls.x;
    let bend_strength = uniforms.controls.y;
    let stiffness = uniforms.controls.z;
    let fade = uniforms.controls.w;

    var push = vec2<f32>(0.0, 0.0);
    let count = min(uniforms.counts.x, 16u);
    for (var i = 0u; i < 16u; i = i + 1u) {
        if (i >= count) {
            break;
        }
        let influencer = uniforms.influencers[i];
        let to_blade = root.xz - influencer.position_radius.xz;
        let dist = length(to_blade);
        let radius = max(influencer.position_radius.w, 0.001);
        let falloff = max(0.0, 1.0 - dist / radius);
        let radial = select(vec2<f32>(0.0, 1.0), to_blade / max(dist, 0.001), dist > 0.001);
        push = push + radial * falloff * influencer.velocity_strength.w;
        push = push + influencer.velocity_strength.xz * falloff * 0.35 * influencer.velocity_strength.w;
    }

    let gust = sin(dot(root.xz, wind_dir * 0.085) + time * wind_speed + phase + variant * 0.73);
    let flutter = sin(dot(root.xz, vec2<f32>(0.19, -0.13)) + time * (wind_speed * 2.7 + 0.4) + phase * 1.7) * 0.22;
    let wind_push = wind_dir * (gust + flutter) * wind_strength;
    let recover = 1.0 - stiffness * 0.58;
    let tip_weight = t * t;
    let bend = (wind_push * 0.42 + push * bend_strength * 0.72) * recover * height * tip_weight;

    let taper = width * mix(1.0, 0.18, t);
    let curl = sin(t * 3.14159265) * width * (0.2 + 0.04 * variant);
    var world = root + terrain_normal * height * t;
    world = world + right * side * taper;
    world = world + forward * curl;
    world = world + vec3<f32>(bend.x, 0.0, bend.y);

    var curved_normal = safeNormalize3(terrain_normal * 0.48 + right * side * 0.42 - forward * (0.18 + 0.22 * t), terrain_normal);
    curved_normal = safeNormalize3(curved_normal + vec3<f32>(bend.x, 0.0, bend.y) * 0.18, terrain_normal);

    var output: VertexOutput;
    output.color = input.color;
    output.world_normal = curved_normal;
    output.blade_uv = vec2<f32>(side * 0.5 + 0.5, t);
    output.position = uniforms.view_proj * vec4<f32>(world, 1.0);
    output.position.z = (output.position.z + output.position.w) * 0.5;
    output.color.a = input.color.a * fade;
    return output;
}
