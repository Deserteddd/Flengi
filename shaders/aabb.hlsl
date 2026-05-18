struct Input {
    float3 position : position;
};

struct Output {
    float4 clipPosition : sv_position;
};

cbuffer VP : register(b0) {
    float4x4 vp;
}

cbuffer PROJ : register(b1) {
    float4x4 modelMat;
};

Output vs_main(Input input) {
    Output output;
    float4 worldPosition = mul(modelMat, float4(input.position, 1));
    output.clipPosition = mul(vp, worldPosition);
    return output;
}

float4 ps_main(Output input) : SV_Target {
    return float4(0, 1, 1, 1);
}