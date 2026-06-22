struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var output: VertexOutput;
    // Fullscreen triangle covering the entire clip-space square via corners
    // (-1,-1), (3,-1), (-1,3) (no vertex buffer needed).
    let tc = vec2<f32>(f32((vertex_index << 1u) & 2u), f32(vertex_index & 2u));
    output.position = vec4<f32>(tc * 2.0 - 1.0, 0.0, 1.0);
    output.uv = vec2<f32>(tc.x, 1.0 - tc.y);
    return output;
}
