cbuffer PointLight : register(b0) {
    float3 lightPosition;
    float3 lightColor;
    float  lightIntensity;
    float3 viewPosition;
};

struct Input {
    float3 position;
    float2 uv;
};


float4 main(Input input) : SV_Target0 {
    return float4(lightColor, 1);
}