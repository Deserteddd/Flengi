#define TAU 6.2831853072

struct Input {
    float3 position : position;
};

struct Output {
    float4 clip_position : sv_position;
    float3 world_position : position;
    float3 normal : normal;
};

cbuffer VP : register(b0) {
    float4x4 vp;
}

cbuffer Global : register(b1) {
    double time;
}

cbuffer FragUBO : register(b0) {
    float3 light_pos;
    float  _pad0;
    float3 light_color;
    float  light_intensity;
    float3 camera_pos;
    float  _pad1;
}

struct WaveParams {
    float2 dir;
    float  wavelength;
    float  amplitude;
    float  speed;
    float  steepness;
};

void apply_gerstner_wave(
    inout float3 pos,
    inout float3 tangent,
    inout float3 bitangent,
    WaveParams w,
    float t,
    float wave_count
) {
    float2 d = normalize(w.dir);
    float k = TAU / w.wavelength;
    float c = sqrt(9.81 / k) * w.speed;
    float f = k * dot(d, pos.xz) + c * t;
    float a = w.amplitude;

    float q = w.steepness / max(k * a * wave_count, 1e-4);
    float cos_f = cos(f);
    float sin_f = sin(f);

    pos.x += d.x * (q * a * cos_f);
    pos.y += a * sin_f;
    pos.z += d.y * (q * a * cos_f);

    float wa = a * k;
    float qwa = q * wa;

    tangent += float3(
        -d.x * d.x * qwa * sin_f,
         d.x * wa * cos_f,
        -d.x * d.y * qwa * sin_f
    );

    bitangent += float3(
        -d.x * d.y * qwa * sin_f,
         d.y * wa * cos_f,
        -d.y * d.y * qwa * sin_f
    );
}

Output vs_main(Input input) {
    Output output;

    float t = (float)time;
    float3 pos = input.position;

    float3 tangent = float3(1, 0, 0);
    float3 bitangent = float3(0, 0, 1);

    WaveParams waves[4] = {
        { float2(1.0, 0.2), 18.0, 0.3, 0.5, 0.7 },
        { float2(0.6, -0.9), 9.0, 0.25, 0.9, 0.6 },
        { float2(-0.7, 0.5), 5.5, 0.2, 1.2, 0.5 },
        { float2(0.3, -0.9), 3.0, 0.12, 1.4, 0.9 }
    };

    [unroll]
    for (uint i = 0; i < 4; ++i) {
        apply_gerstner_wave(pos, tangent, bitangent, waves[i], t, 4.0);
    }

    float3 normal = normalize(cross(bitangent, tangent));

    float4 worldPosition = float4(pos, 1);
    output.clip_position = mul(vp, worldPosition);
    output.world_position = worldPosition.xyz;
    output.normal = normal;
    return output;
}

TextureCube<float4> cubeMap : register(t0);
SamplerState cubeSmp : register(s0);

float3 srgb_to_linear(float3 c) {
    return pow(saturate(c), 2.2);
}

float4 ps_main(Output input) : SV_Target0 {
    float3 N = normalize(input.normal);
    float3 V = normalize(camera_pos - input.world_position);

    float3 R = reflect(-V, N);
    float3 env = srgb_to_linear(cubeMap.Sample(cubeSmp, R).rgb);

    float3 deep_color = float3(0.00, 0.04, 0.1);
    float fresnel = pow(1.0 - saturate(dot(N, V)), 5.0);
    float3 F0 = float3(0.02, 0.02, 0.02);
    float3 F = lerp(F0, 1.0, fresnel);

    float rough = saturate(0.06 + 0.18 * (1.0 - saturate(dot(N, V))));
    env = lerp(env, deep_color, rough);

    float3 color = deep_color * (1.0 - F) + env * F;

    color = color / (color + 1.0);
    color = pow(color, 1.0 / 2.2);
    return float4(color, 0.8);
}