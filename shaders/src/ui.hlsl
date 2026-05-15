struct Input {
    float2 position : position; // in GL clip space (-1..1)
    float2 uv       : uv;
};

struct Output {
    float4 clip_position : SV_Position;
    float2 uv            : uv;
    float4 color         : color;
};

cbuffer UBO {
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