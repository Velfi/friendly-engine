struct SceneUniforms {
    view_proj: mat4x4<f32>,
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
    @location(0) uv: vec2<f32>,
    @location(1) world_pos: vec3<f32>,
    @location(2) world_normal: vec3<f32>,
};

fn instanceModel(input: VertexInput) -> mat4x4<f32> {
    return mat4x4<f32>(input.instance_m0, input.instance_m1, input.instance_m2, input.instance_m3);
}

@vertex
fn main(input: VertexInput) -> VertexOutput {
    var output: VertexOutput;
    output.uv = input.uv;
    let model = instanceModel(input);
    let world_pos = model * input.position;
    output.world_pos = world_pos.xyz;
    let normal_matrix = mat3x3<f32>(
        model[0].xyz,
        model[1].xyz,
        model[2].xyz,
    );
    output.world_normal = normalize(normal_matrix * input.normal);
    output.position = uniforms.view_proj * world_pos;
    output.position.z = (output.position.z + output.position.w) * 0.5;
    return output;
}
