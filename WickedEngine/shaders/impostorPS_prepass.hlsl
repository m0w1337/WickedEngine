#include "globals.hlsli"
#include "impostorHF.hlsli"
#include "objectHF.hlsli"

#if defined(__PSSL__)
#pragma PSSL_target_output_format (target 0 FMT_32_R)
#endif // __PSSL__

uint main(VSOut input, out uint coverage : SV_Coverage STEREO_VIEWID_PARAM) : SV_Target
{
	STEREO_VIEWID_APPLY(stereo_view_id);
	float3 uv_col = float3(input.uv, input.slice);
	float alpha = impostorTex.Sample(sampler_linear_clamp, uv_col).a;
	coverage = AlphaToCoverage(alpha, 0.75, input.GetDither(), input.pos);
	return input.primitiveID;
}
