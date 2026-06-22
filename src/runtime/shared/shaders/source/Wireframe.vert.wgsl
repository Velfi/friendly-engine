struct UniformBlock {
    transform: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> uniforms: UniformBlock;

struct VertexInput {
    @location(0) position: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.color = vec4<f32>(200.0 / 255.0, 210.0 / 255.0, 230.0 / 255.0, 1.0);
    output.position = uniforms.transform * input.position;
    output.position.z = (output.position.z + output.position.w) * 0.5;
    return output;
}
