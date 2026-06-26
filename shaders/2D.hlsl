struct Input {
    float2 position : position; // in GL clip space (-1..1)
    float2 uv       : uv;
};

struct Output {
    float2 uv            : uv;
    float4 color         : color;
    float4 clip_position : SV_Position;
};

cbuffer UBO : register(b0) {
    float4 xywh;         // x, y, width, height in pixels
    float2 screen_size;  // screen width, height in pixels
    bool textured;
    float4 color;
};

Output vs_main(Input input) {
    Output output;

    float2 center_clip = (xywh.xy + xywh.zw * 0.5f) / screen_size * 2.0f - 1.0f;
    float2 half_size_clip = (xywh.zw / screen_size);

    float2 clip_pos = center_clip + input.position * half_size_clip;

    clip_pos.y = -clip_pos.y;

    output.clip_position = float4(clip_pos, 0.0f, 1.0f);
    output.uv = input.uv;
    if (textured) {
        output.color.r = -1;
    } else {
        output.color = color;
    }

    return output;
}

Texture2D<float4> ts0 : register(t0);
SamplerState smp0 : register(s0);

float4 ps_main(Output input) : SV_Target {
    if (input.color.r == -1) {
        return ts0.Sample(smp0, input.uv);
    } else {
        return input.color;
    }
}

Texture2D<float> depth_texture : register(t0);
cbuffer Global : register(b0) {
	float4x4 invProjectionMat;
}

float3 ReconstructViewPos(float2 uv, float depth)
{
    // Muunnetaan UV-koordinaatit NDC-avaruuteen (-1 -> 1)
    float2 ndc;
    ndc.x = uv.x * 2.0f - 1.0f;
    ndc.y = (1.0f - uv.y) * 2.0f - 1.0f; // Varmistetaan Y-akselin suunta

    float ndc_depth = depth; 

    float4 clip = float4(ndc.x, ndc.y, ndc_depth, 1.0f);

    float4 view = mul(invProjectionMat, clip); // HUOM: Järjestys voi olla myös mul(clip, invProjectionMat) riippuen matriisin tyypistä (row-major vs column-major)
    
    // Perspektiivijako (TÄMÄ ON KRIITTINEN: Jos view.w on 0 tai lähellä sitä, jakolasku epäonnistuu)
    if (abs(view.w) > 0.000001f)
    {
        view.xyz /= view.w;
    }

    return view.xyz;
}
float4 ps_fog(Output input) : SV_TARGET
{
    float depth = depth_texture.Sample(smp0, input.uv).r;

    float3 viewPos = ReconstructViewPos(input.uv, depth);
    float dist = length(viewPos);

    float FogStart = 30.0f;
    float FogEnd = 120.0f;
    float fog = saturate((dist - FogStart) / (FogEnd - FogStart));

    float invFog = 1.0f - fog;

    fog = 1.0f - (invFog * invFog * invFog);
    return float4(1, 1, 1, fog);
}




