struct VertexUniforms {
    light_mvp: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> uniforms: VertexUniforms;

struct VertexInput {
    @location(0) position: vec4<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.position = uniforms.light_mvp * input.position;
    output.position.z = (output.position.z + output.position.w) * 0.5;
    return output;
}
