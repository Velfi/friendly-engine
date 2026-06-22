@group(0) @binding(0)
var hdr_color: texture_2d<f32>;

@group(0) @binding(1)
var hdr_sampler: sampler;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

fn logLuminanceAt(uv: vec2<f32>) -> f32 {
    let color = max(textureSampleLevel(hdr_color, hdr_sampler, uv, 0.0).rgb, vec3<f32>(0.0));
    let luma = dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
    return log2(max(luma, 0.0001));
}

@fragment
fn main(input: FragmentInput) -> @location(0) f32 {
    var sum = 0.0;
    var y = 0u;
    loop {
        if (y >= 16u) { break; }
        var x = 0u;
        loop {
            if (x >= 16u) { break; }
            let uv = vec2<f32>((f32(x) + 0.5) / 16.0, (f32(y) + 0.5) / 16.0);
            sum += logLuminanceAt(uv);
            x += 1u;
        }
        y += 1u;
    }
    return sum / 256.0;
}
