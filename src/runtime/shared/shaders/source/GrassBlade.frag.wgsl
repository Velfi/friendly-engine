struct FragmentInput {
    @location(0) color: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) blade_uv: vec2<f32>,
};

fn safeNormalize3(value: vec3<f32>, fallback: vec3<f32>) -> vec3<f32> {
    let len_sq = dot(value, value);
    if (len_sq <= 0.000001) {
        return fallback;
    }
    return value * inverseSqrt(len_sq);
}

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let normal = safeNormalize3(input.world_normal, vec3<f32>(0.0, 1.0, 0.0));
    let key = safeNormalize3(vec3<f32>(0.34, 0.88, 0.25), vec3<f32>(0.0, 1.0, 0.0));
    let wrap = max(dot(normal, key) * 0.5 + 0.5, 0.0);
    let vertical = smoothstep(0.0, 1.0, input.blade_uv.y);
    let midrib = 1.0 - abs(input.blade_uv.x * 2.0 - 1.0);
    let painterly = 0.72 + wrap * 0.32 + midrib * 0.06 + vertical * 0.05;
    let tip_alpha = smoothstep(0.02, 0.18, 1.0 - input.blade_uv.y);
    let alpha = input.color.a * tip_alpha;
    return vec4<f32>(input.color.rgb * painterly, alpha);
}
