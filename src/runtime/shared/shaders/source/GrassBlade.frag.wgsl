struct FragmentInput {
    @location(0) color: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) blade_uv: vec2<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let normal = normalize(input.world_normal);
    let key = normalize(vec3<f32>(0.34, 0.88, 0.25));
    let wrap = max(dot(normal, key) * 0.5 + 0.5, 0.0);
    let vertical = smoothstep(0.0, 1.0, input.blade_uv.y);
    let midrib = 1.0 - abs(input.blade_uv.x * 2.0 - 1.0);
    let painterly = 0.72 + wrap * 0.32 + midrib * 0.06 + vertical * 0.05;
    let tip_alpha = smoothstep(0.02, 0.18, 1.0 - input.blade_uv.y);
    let alpha = input.color.a * tip_alpha;
    return vec4<f32>(input.color.rgb * painterly, alpha);
}
