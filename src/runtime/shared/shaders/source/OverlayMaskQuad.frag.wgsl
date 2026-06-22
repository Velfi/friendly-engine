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
    let coverage = textureSample(texture0, sampler0, input.uv).r;
    return vec4<f32>(input.color.rgb, input.color.a * coverage);
}
