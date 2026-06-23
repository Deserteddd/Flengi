cbuffer SpriteCB : register(b0)
{
    float2 ScreenSize;

    float2 Position;

    float4 SourceRect;

    float2 TextureSize;
};

struct VSInput
{
    float2 Position : Position;   // 0..1 quad
    float2 UV       : UV;  // 0..1 quad
};

struct VSOutput
{
    float4 Position : SV_Position;
    float2 UV       : UV;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;

    //
    // Convert unit quad -> screen pixels
    //
    float2 quadUV = input.Position * 0.5f + 0.5f;
    float2 pixelPos = Position + quadUV * SourceRect.zw;

    //
    // Screen pixels -> NDC
    //
    float2 ndc;
    ndc.x = (pixelPos.x / ScreenSize.x) * 2.0f - 1.0f;
    ndc.y = 1.0f - (pixelPos.y / ScreenSize.y) * 2.0f;

    output.Position = float4(ndc, 0.0f, 1.0f);

    //
    // Keep local UV (0..1)
    //
    output.UV = input.UV;

    return output;
}

Texture2D SpriteTexture : register(t0);
SamplerState SpriteSampler : register(s0);


float4 ps_main(VSOutput input) : SV_TARGET
{
    float2 texUV;

    texUV.x =
        (SourceRect.x + input.UV.x * SourceRect.z)
        / TextureSize.x;

    texUV.y =
        (SourceRect.y + input.UV.y * SourceRect.w)
        / TextureSize.y;

    float4 color = SpriteTexture.Sample(SpriteSampler, texUV);
    color.a = color.r;
    return color;
}