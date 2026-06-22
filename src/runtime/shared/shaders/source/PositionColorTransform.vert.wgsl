struct UniformBlock {
    transform: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> uniforms: UniformBlock;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) color: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
};

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.color = input.color;
    output.position = uniforms.transform * vec4<f32>(input.position, 1.0);
    output.position.z = (output.position.z + output.position.w) * 0.5;
    return output;
}
