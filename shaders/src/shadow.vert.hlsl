
struct Input {
    float3 position : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    uint material : TEXCOORD3;
};

struct Output {
    float4 clipPosition : sv_position;
    float3 position : texcoord0;
};

cbuffer viewproj : register(b0, space1) {
    matrix vp;
};

cbuffer model : register(b1, space1) {
    matrix model;
};

Output main(Input input) {
    float4 worldPosition = mul(model, float4(input.position, 1));
    Output output;
    output.clipPosition = mul(vp, worldPosition);
    output.position = worldPosition.xyz;
    return output;
}