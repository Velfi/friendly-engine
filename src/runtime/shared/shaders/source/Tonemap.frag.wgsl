@group(0) @binding(0)
var hdr_color: texture_2d<f32>;

@group(0) @binding(1)
var hdr_sampler: sampler;

struct ToneMapUniforms {
    exposure: f32,
    min_exposure: f32,
    max_exposure: f32,
    enabled: u32,
};

@group(1) @binding(0)
var<uniform> tone: ToneMapUniforms;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

fn acesFitted(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + vec3<f32>(b))) / (color * (c * color + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));
}

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let hdr = max(textureSample(hdr_color, hdr_sampler, input.uv).rgb, vec3<f32>(0.0));
    let exposure = select(1.0, clamp(tone.exposure, tone.min_exposure, tone.max_exposure), tone.enabled != 0u);
    let mapped = acesFitted(hdr * exposure);
    return vec4<f32>(mapped, 1.0);
}
