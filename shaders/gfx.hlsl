
#define NO_TEX 4294967295

struct Input {
    float3 pos      : pos;
    float3 normal   : normal;
    float2 uv       : uv;
    float4 tangent  : tangent;
};

struct Output {
    float4 clipPosition : sv_position;
    float2 uv       : uv;
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

cbuffer MaterialID : register(b0) {
    uint material_id;
}


float4 ps_main(Output input) : SV_Target {
    Material mat = materials[material_id];
    float4 color = mat.base_color_factor;
    if (mat.base_color_tex != NO_TEX) {
        color = tex_array.Sample(samp, float3(input.uv, mat.base_color_tex));
    }

    return color;
}