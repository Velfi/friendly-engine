struct SceneUniforms {
    light_view_proj: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> uniforms: SceneUniforms;

struct VertexInput {
    @location(0) position: vec4<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) instance_m0: vec4<f32>,
    @location(4) instance_m1: vec4<f32>,
    @location(5) instance_m2: vec4<f32>,
    @location(6) instance_m3: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
};

fn instanceModel(input: VertexInput) -> mat4x4<f32> {
    return mat4x4<f32>(input.instance_m0, input.instance_m1, input.instance_m2, input.instance_m3);
}

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    let model = instanceModel(input);
    output.position = uniforms.light_view_proj * model * input.position;
    output.position.z = (output.position.z + output.position.w) * 0.5;
    return output;
}
