struct Input {
    float3 position : TEXCOORD0;
    float2 uv : TEXCOORD2;
};

struct Output {
    float4 clipPosition : sv_position;
    float3 position : texcoord0;
    float2 uv : texcoord2;
};

cbuffer VP : register(b0) {
    float4x4 vp;
}

cbuffer PROJ : register(b1) {
    float4x4 modelMat;
};

Output main(Input input) {
    Output output;

    float4 worldPosition = mul(modelMat, float4(input.position, 1));
    output.clipPosition = mul(vp, worldPosition);
    output.uv = input.uv;
    output.position = worldPosition.xyz;
    return output;
}