struct Input {
	uint vertexId : SV_VertexID;
};

struct Output {
	float4 clipPosition : SV_Position;
	float3 uv           : uv;
};


cbuffer Global : register(b0) {
    float4x4 invViewMat;
	float4x4 invProjectionMat;
}

Output vs_main(Input input) {
	float2 vertices[] = {
		float2(-1, -1),
		float2( 3, -1),
		float2(-1,  3),
	};
	float4 clipSpacePosition = float4(vertices[input.vertexId], 1, 1);

	float4 viewSpacePosition = mul(invProjectionMat, clipSpacePosition);

	float4 viewDir = mul(invViewMat, float4(viewSpacePosition.xyz, 0));

	Output output;
	output.clipPosition = clipSpacePosition;
	output.uv = viewDir.xyz;
	return output;
}

TextureCube<float4> cubeMap : register(t0);
SamplerState smp : register(s0);


float4 ps_main(Output input) : SV_Target0 {
	return cubeMap.Sample(smp, input.uv);
    // return float4(1, 1, 1, 1);
}
