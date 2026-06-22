struct UniformBlock {
    matrix_transform: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> uniforms: UniformBlock;

struct VertexInput {
    @location(0) position: vec4<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
};

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.uv = input.uv;
    output.color = input.color;
    output.position = uniforms.matrix_transform * input.position;
    return output;
}
