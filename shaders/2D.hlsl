struct Vertex2D {
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

Output vs_main(Vertex2D input) {
    Output output;

    float2 center_clip = (xywh.xy + xywh.zw * 0.5f) / screen_size * 2.0f - 1.0f;
    float2 half_size_clip = (xywh.zw / screen_size);

    float2 clip_pos = center_clip + input.position * half_size_clip;

    clip_pos.y = -clip_pos.y;

    output.clip_position = float4(clip_pos, 0.0f, 1.0f);
    output.uv = input.uv;
    if (textured) { //TODO: Move textured to ps ubo
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


cbuffer Global : register(b0) {
	float4x4 invViewMat;
	float4x4 invProjectionMat;
    float fogStart;
    float fogEnd;
}

Texture2D<float> depth_texture : register(t0);


float3 ReconstructViewPos(float2 uv, float depth)
{
    float2 ndc;
    ndc.x = uv.x * 2.0f - 1.0f;
    ndc.y = (1.0f - uv.y) * 2.0f - 1.0f;

    float ndc_depth = depth; 

    float4 clip = float4(ndc.x, ndc.y, ndc_depth, 1.0f);

    float4 view = mul(invProjectionMat, clip);
    
    if (abs(view.w) > 0.000001f)
    {
        view /= view.w;
    }

    return view.xyz;
}

float4 ps_fog(Output input) : SV_TARGET
{
    float depth = depth_texture.Sample(smp0, input.uv).r;

    // Skip skybox
    // if (depth >= 0.9999f)
    //     return float4(0,0,0,0);

    float3 viewPos = ReconstructViewPos(input.uv, depth);
    float dist = length(viewPos);

    // Distance fog

    float fog = saturate((dist - fogStart) / (fogEnd - fogStart));

    float invFog = 1.0f - fog;
    fog = 1.0f - invFog * invFog * invFog;

    // World-space height
    float4 worldPos = mul(invViewMat, float4(viewPos, 1.0f));

    float FogBottom = 0.0f;
    float FogTop    = 200.0f;

    float heightFog = 1.0f - smoothstep(FogBottom, FogTop, worldPos.y);

    fog *= heightFog;

    return float4(0.6f, 0.6f, 0.6f, fog);
}