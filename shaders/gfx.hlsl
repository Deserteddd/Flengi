
#define NO_TEX 4294967295

struct Input {
    float3 pos      : pos;
    float3 normal   : normal;
    float2 uv       : uv;
    float4 tangent  : tangent;
};

struct Output {
    float4 clipPosition : SV_Position;
    float2 uv            : TEXCOORD0;
    float3 worldPos      : TEXCOORD1;
    float3 normal        : TEXCOORD2;
    float4 tangent       : TEXCOORD3;
};

cbuffer VP : register(b0) {
    float4x4 vp;
}

cbuffer PROJ : register(b1) {
    float4x4 modelMat;
};

Output vs_main(Input input) {
    Output output;

    float4 worldPosition = mul(modelMat, float4(input.pos, 1));
    output.clipPosition = mul(vp, worldPosition);
    output.uv = input.uv;
    output.worldPos = worldPosition.xyz;
    output.normal = normalize(mul((float3x3)modelMat, input.normal));
    output.tangent = float4(normalize(mul((float3x3)modelMat, input.tangent.xyz)), input.tangent.w);
    return output;
}

struct Material {
    float4 base_color_factor;
    float  metallic_factor;
    float  roughness_factor;
    uint   base_color_tex;
    uint   metallic_roughness_tex;
    uint   normal_tex;
    uint   occlusion_tex;
    uint   emissive_tex;
    float3 emissive_factor;
    uint   alpha_mode;
    float  alpha_cutoff;
    uint   double_sided;
    uint   _pad0;
};


Texture2DArray tex_array : register(t0);
SamplerState samp : register(s0);

StructuredBuffer<Material> materials : register(t1);

cbuffer FragUBO : register(b0) {
    float3 light_pos;
    // float _pad;

    float3 light_color;
    float  light_intensity;
    float3 camera_pos;
}

cbuffer MaterialID : register(b1) {
    uint material_id;
}

static const float PI = 3.14159265;

float3 srgb_to_linear(float3 c) {
    return pow(saturate(c), 2.2);
}

float3 fresnel_schlick(float cos_theta, float3 F0) {
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cos_theta), 5.0);
}

float distribution_ggx(float3 N, float3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    return a2 / (PI * denom * denom + 1e-7);
}

float geometry_schlick_ggx(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometry_smith(float3 N, float3 V, float3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = geometry_schlick_ggx(NdotV, roughness);
    float ggx2 = geometry_schlick_ggx(NdotL, roughness);
    return ggx1 * ggx2;
}

float3 get_normal(Output input, uint normal_tex) {
    float3 N = normalize(input.normal);
    if (normal_tex == NO_TEX) {
        return N;
    }

    float3 T = normalize(input.tangent.xyz);
    float3 B = normalize(cross(N, T) * input.tangent.w);
    float3x3 TBN = float3x3(T, B, N);
    float3 normal_ts = tex_array.Sample(samp, float3(input.uv, normal_tex)).xyz * 2.0 - 1.0;
    return normalize(mul(normal_ts, TBN));
}

float4 ps_main(Output input, bool is_front_face : SV_IsFrontFace) : SV_Target {
    Material mat = materials[material_id];
    float4 base_color = mat.base_color_factor;
    if (mat.base_color_tex != NO_TEX) {
        base_color *= tex_array.Sample(samp, float3(input.uv, mat.base_color_tex));
    }

    if (mat.alpha_mode == 1) {
        clip(base_color.a - mat.alpha_cutoff);
    }

    float metallic = mat.metallic_factor;
    float roughness = mat.roughness_factor;
    if (mat.metallic_roughness_tex != NO_TEX) {
        float4 mr = tex_array.Sample(samp, float3(input.uv, mat.metallic_roughness_tex));
        roughness *= mr.g;
        metallic *= mr.b;
    }
    metallic = saturate(metallic);
    roughness = saturate(roughness);

    float3 N = get_normal(input, mat.normal_tex);
    if (mat.double_sided != 0 && !is_front_face) {
        N = -N;
    }

    float3 V = normalize(camera_pos - input.worldPos);
    float3 L = normalize(light_pos - input.worldPos);
    float3 H = normalize(V + L);

    float distance = length(light_pos - input.worldPos);
    float attenuation = 1.0 / max(distance * distance, 0.001);
    float3 radiance = light_color * light_intensity * attenuation;

    float3 albedo = srgb_to_linear(base_color.rgb);
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    float NDF = distribution_ggx(N, H, roughness);
    float G = geometry_smith(N, V, L, roughness);
    float3 F = fresnel_schlick(max(dot(H, V), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denom = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001;
    float3 specular = numerator / denom;

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float NdotL = max(dot(N, L), 0.0);
    float3 Lo = (kD * albedo / PI + specular) * radiance * NdotL;

    float ao = 1.0;
    if (mat.occlusion_tex != NO_TEX) {
        ao = tex_array.Sample(samp, float3(input.uv, mat.occlusion_tex)).r;
    }

    float3 emissive = mat.emissive_factor;
    if (mat.emissive_tex != NO_TEX) {
        emissive *= srgb_to_linear(tex_array.Sample(samp, float3(input.uv, mat.emissive_tex)).rgb);
    }

    float3 ambient = 0.03 * albedo * ao;
    float3 color = ambient + Lo + emissive;

    color = color / (color + 1.0);
    color = pow(color, 1.0 / 2.2);

    return float4(color, base_color.a);
}