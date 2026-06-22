@group(0) @binding(0)
var texture0: texture_2d<f32>;

@group(0) @binding(1)
var sampler0: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let distance = textureSample(texture0, sampler0, input.uv).r;
    let width = max(fwidth(distance), 0.001);
    let coverage = smoothstep(0.5 - width, 0.5 + width, distance);
    return vec4<f32>(input.color.rgb, input.color.a * coverage);
}
