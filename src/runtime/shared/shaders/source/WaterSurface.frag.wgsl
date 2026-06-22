@group(0) @binding(0)
var water_texture: texture_2d<f32>;

@group(0) @binding(1)
var water_sampler: sampler;

struct FragmentInput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    return textureSample(water_texture, water_sampler, input.uv);
}
