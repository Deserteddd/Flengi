struct Input {
    float3 position : TEXCOORD0;
};


float4 main(Input input) : SV_Target0 {
    return float4(normalize(input.position), 1);
}