struct FragmentInput {
    @location(0) uv: vec2<f32>,
    @location(1) world_pos: vec3<f32>,
    @location(2) world_normal: vec3<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let normal = normalize(input.world_normal);
    let light_dir = normalize(vec3<f32>(0.35, 0.85, 0.25));
    let lit = max(dot(normal, light_dir), 0.0);
    let clay = vec3<f32>(0.72, 0.68, 0.60);
    let rim = pow(1.0 - abs(normal.z), 2.0) * 0.08;
    let shade = 0.48 + lit * 0.42 + rim;
    return vec4<f32>(clay * shade, 1.0);
}
