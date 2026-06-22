struct SkyUniforms {
    // Camera basis vectors used to reconstruct a view ray per pixel, matching
    // the CPU projectSkyDirection() math (right/up/forward + fov/aspect).
    camera_right: vec4<f32>,
    camera_up: vec4<f32>,
    camera_forward: vec4<f32>,
    // x = tan(fov_y * 0.5), y = aspect (width / height), z = star_seed (as f32 bits via bitcast), w = star_visibility
    params0: vec4<f32>,
    zenith_color: vec4<f32>,
    horizon_color: vec4<f32>,
    sun_direction: vec4<f32>,
    sun_color: vec4<f32>,
    sun_glow_color: vec4<f32>,
    // x = sun angular radius (deg), y = sun visibility, z = sun enabled (0/1), w unused
    sun_params: vec4<f32>,
    moon_direction: vec4<f32>,
    moon_color: vec4<f32>,
    moon_glow_color: vec4<f32>,
    // x = moon angular radius (deg), y = moon visibility, z = moon enabled (0/1), w unused
    moon_params: vec4<f32>,
    // x = enabled (0/1), y = coverage, z = softness, w = scale
    cloud_params0: vec4<f32>,
    // x = height_bias, y = drift_dir_x, z = drift_dir_y, w = drift_speed
    cloud_params1: vec4<f32>,
    // x = seed, y = parallax_enabled (0/1), z/w unused
    cloud_params2: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> sky: SkyUniforms;

struct FragmentInput {
    @location(0) uv: vec2<f32>,
};

fn hash11(value: f32) -> f32 {
    var x = sin(value * 12.9898) * 43758.5453;
    return fract(x);
}

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let cell = floor(p);
    let local = fract(p);
    let curve = local * local * (vec2<f32>(3.0, 3.0) - 2.0 * local);
    let a = hash21(cell);
    let b = hash21(cell + vec2<f32>(1.0, 0.0));
    let c = hash21(cell + vec2<f32>(0.0, 1.0));
    let d = hash21(cell + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, curve.x), mix(c, d, curve.x), curve.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.54;
    var freq = 1.0;
    var i = 0;
    loop {
        if (i >= 4) {
            break;
        }
        sum += valueNoise(p * freq) * amp;
        freq *= 2.03;
        amp *= 0.5;
        i += 1;
    }
    return sum;
}

// Reconstructs the view ray for a given screen UV (0..1) the same way
// projectSkyDirection() projects a direction into screen space, just inverted.
fn viewRayForUv(uv: vec2<f32>) -> vec3<f32> {
    let tan_half = sky.params0.x;
    let aspect = sky.params0.y;
    let ndc_x = (uv.x * 2.0 - 1.0) * tan_half * aspect;
    let ndc_y = (1.0 - uv.y * 2.0) * tan_half;
    let dir = sky.camera_forward.xyz + sky.camera_right.xyz * ndc_x + sky.camera_up.xyz * ndc_y;
    return normalize(dir);
}

// Procedurally place a star field on the sky sphere by hashing a coarse
// direction-space cell grid, avoiding any CPU-side buffer upload. This trades
// exact positional match with the CPU's LCG-seeded stars for "looks comparable",
// which is within the stated visual bar.
fn starField(dir: vec3<f32>, seed: f32) -> vec3<f32> {
    // Use azimuth/elevation so the star grid is stable across camera moves.
    let elevation = asin(clamp(dir.y, -1.0, 1.0));
    let azimuth = atan2(dir.x, dir.z);
    // Only populate stars away from the horizon, matching the CPU's [8,86] degree band.
    let elev_deg = elevation * 57.29578;
    if (elev_deg < 8.0) {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let cell_size = 0.05;
    let cell = floor(vec2<f32>(azimuth, elevation) / cell_size);
    let cell_hash = hash21(cell + vec2<f32>(seed, seed * 1.37));
    // Sparse: only a fraction of cells contain a star.
    if (cell_hash > 0.12) {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let local = fract(vec2<f32>(azimuth, elevation) / cell_size);
    let star_pos = vec2<f32>(hash21(cell + vec2<f32>(1.0, 0.0) + seed), hash21(cell + vec2<f32>(0.0, 1.0) + seed));
    let dist = length(local - star_pos);
    let twinkle = 0.45 + hash21(cell + vec2<f32>(2.7, 9.1) + seed) * 0.55;
    let warm = hash21(cell + vec2<f32>(5.3, 1.9) + seed);
    let radius = select(0.06, 0.12, twinkle > 0.92);
    let intensity = smoothstep(radius, 0.0, dist) * twinkle;
    let cool = vec3<f32>(182.0, 198.0, 255.0) / 255.0;
    let warmc = vec3<f32>(255.0, 236.0, 196.0) / 255.0;
    let color = mix(cool, warmc, warm * 0.38);
    return color * intensity;
}

fn bodyContribution(dir: vec3<f32>, body_dir: vec3<f32>, angular_radius_deg: f32, visibility: f32, enabled: f32, color: vec3<f32>, glow_color: vec3<f32>, cloud_cover: f32) -> vec3<f32> {
    if (enabled < 0.5 || visibility <= 0.01) {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let cos_angle = clamp(dot(dir, body_dir), -1.0, 1.0);
    let angle_deg = acos(cos_angle) * 57.29578;
    let radius_deg = max(angular_radius_deg, 0.05);
    let glow_radius_deg = radius_deg * 4.0;
    if (angle_deg > glow_radius_deg) {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let glow_t = clamp(1.0 - angle_deg / glow_radius_deg, 0.0, 1.0);
    let disk_t = clamp(1.0 - (angle_deg - radius_deg * 0.78) / (radius_deg * 0.22), 0.0, 1.0);
    let glow_occlusion = mix(1.0, 0.48, clamp(cloud_cover, 0.0, 1.0));
    let disk_occlusion = mix(1.0, 0.18, clamp(cloud_cover, 0.0, 1.0));
    let glow = glow_color * (glow_t * glow_t * visibility * 0.32 * glow_occlusion);
    let disk = color * (disk_t * visibility * disk_occlusion);
    return glow + disk;
}

fn cloudSample(dir: vec3<f32>, uv: vec2<f32>) -> vec4<f32> {
    if (sky.cloud_params0.x < 0.5) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    let coverage = clamp(sky.cloud_params0.y, 0.0, 1.0);
    let softness = clamp(sky.cloud_params0.z, 0.01, 1.0);
    let scale = clamp(sky.cloud_params0.w, 0.05, 8.0);
    let height_bias = clamp(sky.cloud_params1.x, 0.0, 1.0);
    let drift_raw = sky.cloud_params1.yz;
    let drift_len = max(length(drift_raw), 0.001);
    let drift_dir = drift_raw / drift_len;
    let seed = sky.cloud_params2.x;
    let time_s = sky.cloud_params2.z;

    let elevation = clamp(dir.y, 0.0, 1.0);
    let horizon_fade = smoothstep(0.02, 0.22, elevation);
    let zenith_fade = 1.0 - smoothstep(0.78 + height_bias * 0.16, 0.98, elevation);
    let band = horizon_fade * zenith_fade;
    if (band <= 0.001) {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }

    let azimuth = atan2(dir.x, dir.z) * 0.15915494;
    let sphere = vec2<f32>(azimuth, elevation * 1.85);
    let parallax = select(vec2<f32>(0.0, 0.0), (uv - vec2<f32>(0.5, 0.5)) * 0.18, sky.cloud_params2.y > 0.5);
    let seed_offset = vec2<f32>(hash11(seed + 11.0), hash11(seed + 29.0)) * 18.0;
    let drift = drift_dir * sky.cloud_params1.w * time_s;
    let p = (sphere + parallax) * (1.45 / scale) + seed_offset + drift;

    let broad = fbm(p * vec2<f32>(1.15, 0.62));
    let puffs = fbm(p * 2.35 + broad * 0.72);
    let wisps = fbm(p * vec2<f32>(4.4, 1.35) + vec2<f32>(5.7, 1.9));
    let shaped = broad * 0.58 + puffs * 0.34 + wisps * 0.08;
    let threshold = mix(0.74, 0.34, coverage);
    var mask = smoothstep(threshold, threshold + softness * 0.34, shaped) * band;
    mask *= smoothstep(0.0, 0.28, shaped);

    let sun_lift = max(dot(normalize(dir + vec3<f32>(0.0, 0.18, 0.0)), normalize(sky.sun_direction.xyz)), 0.0);
    let daylight = clamp(sky.sun_params.y * sky.sun_params.z, 0.0, 1.0);
    let rim = pow(sun_lift, 4.0) * daylight;
    let underside = clamp((0.55 - elevation) * 1.6, 0.0, 1.0);
    let light = floor(clamp(shaped * 4.0 + rim * 1.6, 0.0, 3.99)) / 3.0;

    let body = vec3<f32>(247.0, 251.0, 242.0) / 255.0;
    let warm = mix(vec3<f32>(255.0, 241.0, 207.0), vec3<f32>(255.0, 199.0, 143.0), clamp(rim * 1.3, 0.0, 1.0)) / 255.0;
    let shadow = mix(vec3<f32>(184.0, 201.0, 232.0), vec3<f32>(180.0, 168.0, 220.0), clamp(rim * 0.6 + underside * 0.35, 0.0, 1.0)) / 255.0;
    var cloud_color = mix(shadow, body, light);
    cloud_color = mix(cloud_color, warm, rim * 0.58);
    cloud_color = mix(cloud_color, sky.horizon_color.rgb, underside * 0.18);
    cloud_color *= mix(0.24, 1.0, daylight);

    return vec4<f32>(cloud_color, clamp(mask * 0.88, 0.0, 0.88));
}

fn sunShaftContribution(dir: vec3<f32>, cloud_alpha: f32) -> vec3<f32> {
    if (sky.sun_params.z < 0.5 || sky.sun_params.y <= 0.01) {
        return vec3<f32>(0.0, 0.0, 0.0);
    }
    let sun_alignment = max(dot(dir, normalize(sky.sun_direction.xyz)), 0.0);
    let cone = pow(sun_alignment, 18.0) * sky.sun_params.y;
    let break_light = smoothstep(0.08, 0.52, cloud_alpha) * (1.0 - smoothstep(0.62, 0.92, cloud_alpha));
    let streak_noise = 0.55 + 0.45 * fbm(vec2<f32>(atan2(dir.x, dir.z) * 12.0, dir.y * 4.0) + vec2<f32>(sky.cloud_params2.x, sky.cloud_params2.x));
    let strength = cone * break_light * streak_noise * 0.24;
    return sky.sun_glow_color.rgb * strength;
}

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let dir = viewRayForUv(input.uv);

    // Vertical gradient matches paintSkyGradient(): t derived from screen-space
    // row position, raised to 1.8 to bias toward the horizon color near the bottom.
    let t = clamp(input.uv.y, 0.0, 1.0);
    let horizon_mix = clamp(pow(t, 1.8), 0.0, 1.0);
    var color = mix(sky.zenith_color.rgb, sky.horizon_color.rgb, horizon_mix);

    let star_visibility = sky.params0.w;
    if (star_visibility > 0.001) {
        color += starField(dir, sky.params0.z) * star_visibility;
    }

    let clouds = cloudSample(dir, input.uv);
    color = mix(color, clouds.rgb, clouds.a);
    color += sunShaftContribution(dir, clouds.a);

    color += bodyContribution(dir, sky.sun_direction.xyz, sky.sun_params.x, sky.sun_params.y, sky.sun_params.z, sky.sun_color.rgb, sky.sun_glow_color.rgb, clouds.a);
    color += bodyContribution(dir, sky.moon_direction.xyz, sky.moon_params.x, sky.moon_params.y, sky.moon_params.z, sky.moon_color.rgb, sky.moon_glow_color.rgb, clouds.a);

    return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}
